"""MediaPipe Face Mesh over OpenVINO: a frame in, 468 landmarks out.

This is the only module that touches an inference runtime. It drives the two
MediaPipe TFLite models directly -- OpenVINO's TFLite frontend reads them
without a conversion step -- and reimplements the small amount of graph glue
MediaPipe would otherwise provide around them. The geometry for that glue
lives in mouthguard_core, which stays importable without OpenVINO so it can
be tested on its own.
"""

import math

import numpy as np

from mouthguard_core import (
    DETECTOR_INPUT_SIZE,
    DETECTOR_MIN_SCORE,
    DETECTOR_MODEL,
    LANDMARK_INPUT_SIZE,
    LANDMARK_MODEL,
    NUM_LANDMARKS,
    decode_detection,
    order_devices,
    project_landmarks,
    rect_from_detection,
    rect_from_landmarks,
    should_redetect,
    sigmoid,
    ssd_anchors,
)


class FaceMesh:
    """Stateful tracker: detect once, then follow the mesh frame to frame."""

    def __init__(self, model_dir, device=None):
        import os

        import cv2
        import openvino as ov

        self._cv2 = cv2
        core = ov.Core()
        detector = core.read_model(os.path.join(model_dir, DETECTOR_MODEL))
        landmarker = core.read_model(os.path.join(model_dir, LANDMARK_MODEL))

        # Compilation is where the device-specific cost sits (a few seconds on
        # GPU, a fraction of a second on CPU); inference afterwards is about a
        # millisecond per model. Both are compiled up front so no frame pays
        # for it mid-session.
        #
        # A device can be enumerated and still fail to compile -- an NPU whose
        # kernel driver is present but whose userspace compiler is not is the
        # live example, and it is not a reason to leave the user without a
        # working camera. So each candidate is tried in turn and the first one
        # that actually compiles both models wins. CPU is last and is assumed
        # to work; if it does not, the exception propagates.
        errors = []
        for candidate in self._candidates(core, device):
            try:
                self._detector = core.compile_model(detector, candidate)
                self._landmarker = core.compile_model(landmarker, candidate)
            except Exception as exc:  # noqa: BLE001 - try the next device
                errors.append(f"{candidate}: {str(exc).splitlines()[-1]}")
                continue
            self.device = candidate
            break
        else:
            raise RuntimeError("no usable inference device -- " + "; ".join(errors))

        self._anchors = ssd_anchors()
        self._rect = None
        self._presence = None

    @staticmethod
    def _candidates(core, device):
        """Devices to try compiling on, best first.

        An explicit --inference-device is honoured with no fallback: someone
        naming a device wants to know when it does not work, not to silently
        get a different one.
        """
        if device:
            return [device]
        ordered = order_devices(core.available_devices)
        # CPU is the guaranteed floor even if the plugin somehow went
        # unenumerated, so the fallback chain always ends somewhere real.
        if "CPU" not in ordered:
            ordered.append("CPU")
        return ordered

    def reset(self):
        """Forget the tracked face, forcing a detection on the next frame.

        Called when the camera stops and restarts: the face behind the lens
        may be somewhere else entirely by then, and a stale region of
        interest would have the landmark model reporting confident nonsense
        about a patch of wall.
        """
        self._rect = None
        self._presence = None

    def __call__(self, frame):
        """Landmarks in frame pixels, or None when no face is present."""
        h, w = frame.shape[:2]

        if should_redetect(self._rect is not None, self._presence):
            hit = self._detect(frame)
            if hit is None:
                self.reset()
                return None
            box, keypoints = hit
            self._rect = rect_from_detection(box, keypoints, w, h)

        points, presence = self._landmarks(frame, self._rect)
        self._presence = presence
        if presence < 0.5:
            # Keep the rect: should_redetect will send the next frame through
            # the detector, and clearing it here would only lose information.
            return None

        self._rect = rect_from_landmarks(points, w, h)
        return points

    # --- BlazeFace ---------------------------------------------------------
    def _detect(self, frame):
        """Highest-scoring face in the frame, in frame-relative coordinates."""
        tensor, scale, pad_x, pad_y = self._letterbox(frame)
        out = self._detector([tensor])
        regressors = out[self._detector.output("regressors")][0]
        scores = out[self._detector.output("classificators")][0]

        best = int(np.argmax(scores[:, 0]))
        if sigmoid(float(scores[best, 0])) < DETECTOR_MIN_SCORE:
            return None

        box, keypoints = decode_detection(regressors[best], self._anchors[best])
        # Undo the letterbox: the model saw a padded square, the caller works
        # in the camera's real aspect ratio.
        h, w = frame.shape[:2]

        def unpad(x, y):
            return ((x * DETECTOR_INPUT_SIZE - pad_x) / scale / w,
                    (y * DETECTOR_INPUT_SIZE - pad_y) / scale / h)

        xmin, ymin, bw, bh = box
        x0, y0 = unpad(xmin, ymin)
        x1, y1 = unpad(xmin + bw, ymin + bh)
        return (x0, y0, x1 - x0, y1 - y0), [unpad(*kp) for kp in keypoints]

    def _letterbox(self, frame):
        """Aspect-preserving resize into the detector's square input.

        MediaPipe pads rather than stretches, and the model was trained that
        way -- squashing a 4:3 frame into a square measurably degrades the
        detection score on faces near the edges.
        """
        cv2 = self._cv2
        h, w = frame.shape[:2]
        scale = DETECTOR_INPUT_SIZE / max(w, h)
        new_w, new_h = round(w * scale), round(h * scale)
        resized = cv2.resize(frame, (new_w, new_h), interpolation=cv2.INTER_AREA)

        canvas = np.zeros((DETECTOR_INPUT_SIZE, DETECTOR_INPUT_SIZE, 3), np.uint8)
        pad_x = (DETECTOR_INPUT_SIZE - new_w) // 2
        pad_y = (DETECTOR_INPUT_SIZE - new_h) // 2
        canvas[pad_y:pad_y + new_h, pad_x:pad_x + new_w] = resized

        rgb = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB).astype(np.float32)
        # BlazeFace wants [-1, 1]; the landmark model below wants [0, 1].
        tensor = (rgb / 127.5 - 1.0)[None, ...]
        return tensor, scale, pad_x, pad_y

    # --- landmark model ----------------------------------------------------
    def _landmarks(self, frame, rect):
        crop = self._crop(frame, rect)
        rgb = self._cv2.cvtColor(crop, self._cv2.COLOR_BGR2RGB).astype(np.float32)
        out = self._landmarker([(rgb / 255.0)[None, ...]])

        raw = None
        presence = 0.0
        for value in out.values():
            flat = np.asarray(value).reshape(-1)
            # The two outputs are told apart by size, not by name: the model's
            # tensor names are autogenerated ("conv2d_21", "conv2d_31") and
            # are not part of any published contract.
            if flat.size == NUM_LANDMARKS * 3:
                raw = flat
            elif flat.size == 1:
                presence = sigmoid(float(flat[0]))

        if raw is None:
            raise RuntimeError("landmark model returned no 1404-value tensor")
        return project_landmarks(raw, rect), presence

    def _crop(self, frame, rect):
        """Extract the rotated square region as a LANDMARK_INPUT_SIZE image."""
        cx, cy, side, _, angle = rect
        s = side / LANDMARK_INPUT_SIZE
        half = LANDMARK_INPUT_SIZE / 2
        cos_a, sin_a = math.cos(angle) * s, math.sin(angle) * s
        # Maps destination (crop) pixels back to source (frame) pixels, which
        # is why warpAffine is called with WARP_INVERSE_MAP -- the same
        # rotation project_landmarks applies in reverse to put the resulting
        # landmarks back in frame coordinates.
        matrix = np.array([
            [cos_a, -sin_a, cx - half * cos_a + half * sin_a],
            [sin_a, cos_a, cy - half * sin_a - half * cos_a],
        ], dtype=np.float32)
        return self._cv2.warpAffine(
            frame, matrix, (LANDMARK_INPUT_SIZE, LANDMARK_INPUT_SIZE),
            flags=self._cv2.INTER_LINEAR | self._cv2.WARP_INVERSE_MAP,
            borderMode=self._cv2.BORDER_CONSTANT)
