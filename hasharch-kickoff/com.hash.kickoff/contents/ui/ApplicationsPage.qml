/*
 * SPDX-FileCopyrightText: 2021 Noah Davis <noahadvs@gmail.com>
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Templates as T
import org.kde.plasma.private.kicker as Kicker
import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kitemmodels as KItemModels
import org.kde.plasma.plasma5support as P5Support

BasePage {
    id: root

    // The curated HasH-Arch categories shown in the Applications sidebar. Loaded
    // live from `hash-cat list-groups`, so groups added via right-click appear.
    property var hashCategories: [
        "Office", "Games", "Development",
        "Internet & Communication", "Media", "Creation"
    ]
    KItemModels.KSortFilterProxyModel {
        id: sideBarFilter
        sourceModel: kickoff.rootModel
        filterRowCallback: (sourceRow, sourceParent) => {
            if (sourceParent.valid) return true;   // children of a category
            if (sourceRow === 0) return true;      // Favourites (kept at the top)
            const name = kickoff.rootModel.data(
                kickoff.rootModel.index(sourceRow, 0, sourceParent), Qt.DisplayRole);
            return root.hashCategories.indexOf(String(name)) !== -1;
        }
    }

    // ---- right-click: manage groups (via hash-cat); apps are managed by
    // right-clicking the app itself in the content area (see AbstractKickoffItemDelegate) ----
    P5Support.DataSource {
        id: catExe
        engine: "executable"
        connectedSources: []
        onNewData: function(src, data) {
            catExe.disconnectSource(src);
            if (src.indexOf("groups.json") >= 0) {
                try {
                    const gs = JSON.parse(data["stdout"] || "{}").groups || [];
                    root.hashCategories = gs.map(g => g.name);
                    kickoff.hashGroups = gs.map(g => ({ name: g.name, slug: g.slug }));
                    const cb = sideBarFilter.filterRowCallback;   // re-run the filter
                    sideBarFilter.filterRowCallback = (a, b) => cb(a, b);
                } catch (e) { /* keep defaults */ }
            }
        }
    }
    readonly property string catBin: "/home/hash/.local/bin/hash-cat"
    function reloadGroups() { catExe.connectSource("cat /home/hash/.local/share/com.hash.kickoff/groups.json 2>/dev/null") }
    function runCat(cmd) { catExe.connectSource(root.catBin + " " + cmd); reloadSoon.restart(); }
    Timer { id: reloadSoon; interval: 1500; repeat: true; triggeredOnStart: false
            property int n: 0
            onTriggered: { root.reloadGroups(); n++; if (n > 8) { stop(); n = 0; } } }
    Component.onCompleted: reloadGroups()
    Connections {
        target: kickoff
        function onExpandedChanged() { if (kickoff.expanded) root.reloadGroups(); }
    }

    // empty space in the sidebar -> add things
    QQC2.Menu {
        id: ctxMenu
        QQC2.MenuItem { text: i18n("New Group…");       icon.name: "folder-new"; onTriggered: root.runCat("add-group") }
        QQC2.MenuItem { text: i18n("Add Application…"); icon.name: "list-add";   onTriggered: root.runCat("add-app") }
    }
    // right-click a specific group -> add an app to it / remove the group
    QQC2.Menu {
        id: groupCtxMenu
        property string slug: ""
        QQC2.MenuItem { text: i18n("Add Application…"); icon.name: "list-add"
            onTriggered: root.runCat("add-app " + groupCtxMenu.slug) }
        QQC2.MenuSeparator {}
        QQC2.MenuItem { text: i18n("Remove Group");     icon.name: "edit-delete"
            onTriggered: root.runCat("remove-group " + groupCtxMenu.slug) }
    }

    sideBarComponent: KickoffListView {
        id: sideBar
        focus: true // needed for Loaders
        model: sideBarFilter
        isSidebar: true
        // needed otherwise app displayed at top-level will show a first character as group.
        section.property: ""
        delegate: KickoffListDelegate {
            id: sideBarDelegate
            width: view.availableWidth
            isCategoryListItem: true
            background: PlasmaExtras.Highlight {
                // I have to do this for it to actually fill the item for some reason
                anchors.fill: parent
                active: false
                hovered: sideBarDelegate.mouseArea.containsMouse
                visible: !Plasmoid.configuration.switchCategoryOnHover
                    && !sideBarDelegate.isSeparator && !sideBarDelegate.ListView.isCurrentItem
                    && hovered
            }
            // right-click a group -> add app to it / remove it (Favourites -> general menu)
            TapHandler {
                acceptedButtons: Qt.RightButton
                gesturePolicy: TapHandler.ReleaseWithinBounds
                onTapped: {
                    const g = (kickoff.hashGroups || []).find(x => x.name === sideBarDelegate.text);
                    if (g) { groupCtxMenu.slug = g.slug; groupCtxMenu.popup(); }
                    else { ctxMenu.popup(); }
                }
            }
        }
        // right-click empty space in the category sidebar -> add a group / app
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: ctxMenu.popup()
        }
    }

    contentAreaComponent: VerticalStackView {
        id: stackView

        popEnter: Transition {
            NumberAnimation {
                property: "x"
                from: 0.5 * root.width
                to: 0
                duration: Kirigami.Units.longDuration
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: Kirigami.Units.longDuration
                easing.type: Easing.OutCubic
            }
        }

        pushEnter: Transition {
            NumberAnimation {
                property: "x"
                from: 0.5 * -root.width
                to: 0
                duration: Kirigami.Units.longDuration
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                property: "opacity"
                from: 0.0
                to: 1.0
                duration: Kirigami.Units.longDuration
                easing.type: Easing.OutCubic
            }
        }

        readonly property string preferredFavoritesViewObjectName: Plasmoid.configuration.favoritesDisplay === 0 ? "favoritesGridView" : "favoritesListView"
        readonly property Component preferredFavoritesViewComponent: Plasmoid.configuration.favoritesDisplay === 0 ? favoritesGridViewComponent : favoritesListViewComponent
        readonly property string preferredAllAppsViewObjectName: Plasmoid.configuration.applicationsDisplay === 0 ? "listOfGridsView" : "applicationsListView"
        readonly property Component preferredAllAppsViewComponent: Plasmoid.configuration.applicationsDisplay === 0 ? listOfGridsViewComponent : applicationsListViewComponent

        readonly property string preferredAppsViewObjectName: Plasmoid.configuration.applicationsDisplay === 0 ? "applicationsGridView" : "applicationsListView"
        readonly property Component preferredAppsViewComponent: Plasmoid.configuration.applicationsDisplay === 0 ? applicationsGridViewComponent : applicationsListViewComponent
        // NOTE: The 0 index modelForRow isn't supposed to be used. That's just how it works.
        // But to trigger model data update, set initial value to 0
        property int appsModelRow: 0
        readonly property Kicker.AppsModel appsModel: kickoff.rootModel.modelForRow(appsModelRow)
        Connections {
            target: kickoff.rootModel
            function onRefreshed() { // recalculate appsModel binding on rootModel refresh;
                stackView.appsModelRowChanged() // modelForRow does not create dependency
            }
        }
        focus: true
        initialItem: preferredFavoritesViewComponent   // Favourites shows first

        function showSectionView(sectionName: string, parentView: KickoffListView): void {
            stackView.push(applicationsSectionViewComponent, {
                currentSection: sectionName,
                parentView,
            });
        }

        Component {
            id: favoritesListViewComponent
            DropAreaListView {
                id: favoritesListView
                objectName: "favoritesListView"
                mainContentView: true
                focus: true
                model: kickoff.rootModel.favoritesModel
            }
        }

        Component {
            id: favoritesGridViewComponent
            DropAreaGridView {
                id: favoritesGridView
                objectName: "favoritesGridView"
                focus: true
                model: kickoff.rootModel.favoritesModel
            }
        }

        Component {
            id: applicationsListViewComponent

            KickoffListView {
                id: applicationsListView
                objectName: "applicationsListView"
                mainContentView: true
                model: stackView.appsModel
                // we want to semantically switch between group and "", disabling grouping, workaround for QTBUG-121797
                section.property: model && model.description === "KICKER_ALL_MODEL" ? "group" : "_unset"
                section.criteria: ViewSection.FirstCharacter
                hasSectionView: stackView.appsModelRow === 1

                onShowSectionViewRequested: sectionName => {
                    stackView.showSectionView(sectionName, this);
                }
            }
        }

        Component {
            id: applicationsSectionViewComponent

            SectionView {
                id: sectionView
                model: stackView.appsModel.sections

                onHideSectionViewRequested: index => {
                    stackView.pop();
                    stackView.currentItem.view.positionViewAtIndex(index, ListView.Beginning);
                    stackView.currentItem.currentIndex = index;
                }
            }
        }

        Component {
            id: applicationsGridViewComponent
            KickoffGridView {
                id: applicationsGridView
                objectName: "applicationsGridView"
                model: stackView.appsModel
            }
        }

        Component {
            id: listOfGridsViewComponent

            ListOfGridsView {
                id: listOfGridsView
                objectName: "listOfGridsView"
                mainContentView: true
                gridModel: stackView.appsModel

                onShowSectionViewRequested: sectionName => {
                    stackView.showSectionView(sectionName, this);
                }
            }
        }

        onPreferredFavoritesViewComponentChanged: {
            if (root.sideBarItem !== null && root.sideBarItem.currentIndex === 0) {
                stackView.replace(stackView.preferredFavoritesViewComponent)
            }
        }
        onPreferredAllAppsViewComponentChanged: {
            if (root.sideBarItem !== null && root.sideBarItem.currentIndex === 1) {
                stackView.replace(stackView.preferredAllAppsViewComponent)
            }
        }
        onPreferredAppsViewComponentChanged: {
            if (root.sideBarItem !== null && root.sideBarItem.currentIndex > 1) {
                stackView.replace(stackView.preferredAppsViewComponent)
            }
        }

        Connections {
            target: root.sideBarItem
            function onCurrentIndexChanged() {
                // The sidebar is a FILTERED proxy (Favourites + our curated categories),
                // so map the proxy index back to the real rootModel row.
                if (!root.sideBarItem || root.sideBarItem.currentIndex < 0) return;
                const srcRow = sideBarFilter.mapToSource(
                    sideBarFilter.index(root.sideBarItem.currentIndex, 0)).row;
                if (srcRow === 0) {   // Favourites
                    kickoff.currentHashSlug = "";
                    if (stackView.currentItem.objectName !== stackView.preferredFavoritesViewObjectName)
                        stackView.replace(stackView.preferredFavoritesViewComponent)
                    return;
                }
                // navigate FIRST so this can never block category switching
                stackView.appsModelRow = srcRow;
                if (stackView.currentItem.objectName !== stackView.preferredAppsViewObjectName) {
                    stackView.replace(stackView.preferredAppsViewComponent)
                }
                // best-effort: tell delegates which group is open (for "Remove from group").
                // sidebar order is [Favourites, group0, group1, ...] so index-1 maps to hashGroups.
                try {
                    const g = (kickoff.hashGroups || [])[root.sideBarItem.currentIndex - 1];
                    kickoff.currentHashSlug = (g && g.slug) ? g.slug : "";
                } catch (e) { kickoff.currentHashSlug = ""; }
            }
        }
        Connections {
            target: kickoff
            function onExpandedChanged() {
                if (!kickoff.expanded && kickoff.contentArea.currentItem) {
                    kickoff.contentArea.currentItem.forceActiveFocus()
                }
            }
        }
    }
    // NormalPage doesn't get destroyed when deactivated, so the binding uses
    // StackView.status and visible. This way the bindings are reset when
    // NormalPage is Activated again.
    Binding {
        target: kickoff
        property: "sideBar"
        value: root.sideBarItem
        when: root.T.StackView.status === T.StackView.Active && root.visible
        restoreMode: Binding.RestoreBinding
    }
    Binding {
        target: kickoff
        property: "contentArea"
        value: root.contentAreaItem.currentItem // NOT just root.contentAreaItem
        when: root.T.StackView.status === T.StackView.Active && root.visible
        restoreMode: Binding.RestoreBinding
    }
}
