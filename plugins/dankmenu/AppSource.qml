import QtQuick
import Quickshell
import qs.Common
import qs.Services

// The plugin's own app list. DMS's launcher search is not reachable from a
// plugin, and reaching for it would couple this menu to the spotlight it
// replaces -- so the listing, the captions and the ranking are local. The one
// thing that is deliberately NOT reimplemented is launching: SessionService
// knows about uwsm and systemd scopes, and getting that wrong silently breaks
// process accounting for every app started from here.
Item {
    id: root

    // Frecency nudges an app up a match. Search.js adds a boost only to
    // entries that already matched, so this never conjures a result out of
    // nothing. Logarithmic and capped: the tenth launch should matter far less
    // than the second, and no app should outrank an exact-name match forever.
    function boostFor(entry) {
        const usage = AppUsageHistoryData.appUsageRanking || {};
        const record = usage[entry.id] || usage[entry.execString] || null;
        if (!record)
            return 0;
        return Math.min(12, Math.log(1 + (record.usageCount || 0)) * 4);
    }

    function entries() {
        const apps = DesktopEntries.applications.values;
        const out = [];
        for (let i = 0; i < apps.length; i++) {
            const app = apps[i];
            if (app.noDisplay)
                continue;
            out.push({
                id: "app:" + app.id,
                appId: app.id,
                label: app.name,
                icon: app.icon || "application-x-executable",
                comment: app.genericName || app.comment || "Apps",
                kind: "app",
                aliases: app.keywords || [],
                checked: false,
                disabled: false,
                boost: boostFor(app)
            });
        }
        return out;
    }

    function launch(row) {
        const apps = DesktopEntries.applications.values;
        for (let i = 0; i < apps.length; i++) {
            if (apps[i].id !== row.appId)
                continue;
            SessionService.launchDesktopEntry(apps[i]);
            AppUsageHistoryData.addAppUsage(apps[i]);
            return;
        }
        console.warn("dankMenu: no desktop entry for", row.appId);
    }
}
