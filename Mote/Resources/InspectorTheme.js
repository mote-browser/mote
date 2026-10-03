(() => {
    // Runs only in WebKit's inspector frontend, never in the inspected page.
    const WI = window.WI;
    const host = window.InspectorFrontendHost;
    if (!WI?.tabBar || !WI?.tabBrowser || !host?.requestSetDockSide || !WI.updateDockedState)
        return false;
    if (document.getElementById("mote-inspector-rail")) return true;

    // Use WebKit's own two-pane option instead of forcing sidebar geometry.
    if (WI.settings?.enableElementsTabIndependentStylesDetailsSidebarPanel)
        WI.settings.enableElementsTabIndependentStylesDetailsSidebarPanel.value = false;

    const style = document.createElement("style");
    style.id = "mote-inspector-theme";
    style.textContent = moteCSS;
    document.head.append(style);
    document.body.classList.add("mote-inspector");
    const rail = document.createElement("nav");
    rail.id = "mote-inspector-rail";
    rail.setAttribute("aria-label", "Developer tools");
    document.body.append(rail);
    const toolItems = () => WI.tabBar.tabBarItems
        .map((item, index) => ({item, index, title: item.displayName || item.title}))
        .filter(({item, title}) => item.representedObject && title);
    const iconData = (item) => {
        const icon = item.element?.querySelector("img");
        if (!icon?.complete || !icon.naturalWidth) return "";
        try {
            const canvas = document.createElement("canvas");
            canvas.width = canvas.height = 36;
            canvas.getContext("2d").drawImage(icon, 0, 0, 36, 36);
            return canvas.toDataURL("image/png");
        } catch { return ""; }
    };
    const send = (action, value) => window.webkit.messageHandlers.moteInspector.postMessage({action, value,
        tabs: toolItems().map(({item, index, title}) => ({title, index,
            icon: tabs.querySelector(`button[data-tab-index="${index}"] img`)?.src || "",
            selected: item === WI.tabBar.selectedTabBarItem}))});
    const button = (label, symbol, action) => {
        const control = document.createElement("button");
        control.type = "button";
        control.title = label;
        control.setAttribute("aria-label", label);
        control.textContent = symbol;
        control.onclick = action;
        rail.append(control);
        return control;
    };
    let collapsed = false;
    const setCollapsed = (value) => {
        collapsed = value;
        document.body.classList.toggle("mote-collapsed", value);
        fold.title = value ? "Expand developer tools" : "Collapse developer tools";
        fold.setAttribute("aria-label", fold.title);
        fold.setAttribute("aria-expanded", String(!value));
        fold.textContent = value ? "‹" : "›";
        send("collapse", value);
        WI.tabBrowser.needsLayout?.();
        if (value) fold.focus();
    };
    const fold = button("Collapse developer tools", "›", () => setCollapsed(!collapsed));
    fold.setAttribute("aria-expanded", "true");
    const tabs = document.createElement("div");
    tabs.className = "mote-inspector-tabs";
    rail.append(tabs);
    const heading = document.createElement("span");
    heading.id = "mote-inspector-title";
    WI.tabBar.element.append(heading);
    const loadingIcons = new WeakSet();
    const rebuildTabs = () => {
        tabs.replaceChildren();
        document.body.classList.toggle("mote-elements", WI.tabBar.selectedTabBarItem?.representedObject?.type === "elements");
        heading.textContent = WI.tabBar.selectedTabBarItem?.displayName || "Developer tools";
        for (const {item, title, index} of toolItems()) {
            const control = document.createElement("button");
            control.type = "button";
            control.dataset.tabIndex = index;
            control.title = title;
            control.setAttribute("aria-label", title);
            control.setAttribute("aria-pressed", String(item === WI.tabBar.selectedTabBarItem));
            // Both rails use this exact image; no second SF Symbol mapping.
            const source = iconData(item);
            const original = item.element?.querySelector("img");
            if (original && !original.complete && !loadingIcons.has(original)) {
                loadingIcons.add(original);
                original.addEventListener("load", rebuildTabs, {once: true});
            }
            if (source) {
                const icon = new Image();
                icon.src = source;
                icon.alt = "";
                control.append(icon);
            }
            else control.textContent = title.slice(0, 2);
            control.onclick = () => {
                if (collapsed) setCollapsed(false);
                WI.tabBrowser.showTabForContentView(item.representedObject);
            };
            tabs.append(control);
        }
    };
    for (const event of ["TabBarItemAdded", "TabBarItemRemoved", "TabBarItemSelected", "TabBarItemsReordered"]) {
        if (WI.TabBar?.Event[event]) WI.tabBar.addEventListener(WI.TabBar.Event[event], rebuildTabs);
    }
    const popout = button("Open in separate window", "↗", () => {
        if (collapsed) setCollapsed(false);
        host.requestSetDockSide(WI.dockConfiguration === "undocked" ? "right" : "undocked");
    });
    popout.className = "mote-inspector-popout";
    button("Close developer tools", "×", () => send("close"));

    const updateDockedState = WI.updateDockedState;
    WI.updateDockedState = function(side) {
        if (side === "left" || side === "bottom") {
            host.requestSetDockSide("right");
            return;
        }
        if (collapsed && side === "undocked") setCollapsed(false);
        updateDockedState.call(this, side);
        WI._previousDockConfiguration = "right";
        fold.hidden = side === "undocked";
        popout.title = side === "undocked" ? "Dock to right" : "Open in separate window";
        popout.setAttribute("aria-label", popout.title);
        popout.textContent = side === "undocked" ? "↙" : "↗";
    };
    WI._dockLeft = WI._dockBottom = () => host.requestSetDockSide("right");
    window.moteInspector = {
        expand: () => setCollapsed(false),
        selectTab: (index) => {
            const item = WI.tabBar.tabBarItems[index];
            if (item?.representedObject) WI.tabBrowser.showTabForContentView(item.representedObject);
        }
    };
    rebuildTabs();
    // Start every new frontend on the right, independent of WebKit's saved dock.
    host.requestSetDockSide("right");
    return true;
})();
