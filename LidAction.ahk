#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; https://www.autohotkey.com/boards/viewtopic.php?p=485503#p485503
#Include StdoutToVar.ahk

acdcs := ["AC", "DC"]

; translatable messages
m := {
    acdcs: ["AC⚡", "DC🔋", "Both"]
    , actions: ["Nothing", "Sleep", "Hibernate", "Shutdown"]
    , progname: "LidAction"
    , exit: "Exit"
    , opengui: "Open GUI"
    , apply: "Apply"
    , ok: "OK"
}
/* m := {
    acdcs: ["電源あり", "バッテリ", "両方とも"]
    , actions: ["何もしない", "スリープ", "休止", "シャットダウン"]
    , progname: "フタ閉じ電源設定"
    , exit: "終了"
    , opengui: "GUI起動"
    , apply: "適用"
    , ok: "OK"
} */
A_IconTip := m.progname
TraySetIcon("shell32.dll", -284)

guids := getguids()

; the first character of the filename decides how it works
; !G will stay in the tray (useful for startup)
if (StrUpper(SubStr(A_ScriptName, 1, 1) != "G")) {
    ; events on which the tray icon shows the menu
    triggers := Map(
        0x205, "right click"
        ; , 0x200, "hover",
        ; , 0x202, "click - will disable double-click action",
    )
    OnMessage(0x404, showmenu.Bind(guids)) ; tray icon
    Persistent()
    return
}
; if the filename starts with G, show one-time GUI
; without a tray icon
A_IconHidden := true
opengui(guids)
return


; returns an object
; note that powercfg messages are localized
getguids() {
    powercfg := StdoutToVar("powercfg /query scheme_current sub_buttons")
    if (powercfg.ExitCode) {
        MsgBox("powercfg failed:`r`n" . powercfg.Output)
        ExitApp()
    }
    lines := StrSplit(powercfg.Output, "`n", " `r")
    if (lines.Length < 4) {
        MsgBox("powercfg incompatible:`r`n" . powercfg.Output)
        ExitApp()
    }

    guidregex := " ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) "
    if ( not RegExMatch(lines[1], guidregex, &scheme_current)) {
        MsgBox("scheme_current not found:`r`n" . lines[1])
        ExitApp()
    }
    if ( not RegExMatch(lines[3], guidregex, &sub_buttons)) {
        MsgBox("sub_buttons not found:`r`n" . lines[3])
        ExitApp()
    }

    return {
        scheme_current: scheme_current[1]
        , sub_buttons: sub_buttons[1]
            ; https://learn.microsoft.com/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action
        , lidaction: "5ca83367-6e45-459f-a27b-476b1d01c936" ; not available from powercfg
    }
}

; admin priv is not needed here
getcurvalues(guids) {
    global acdcs

    regpath := Format(
        "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\{}\{}\{}",
        guids.scheme_current,
        guids.sub_buttons,
        guids.lidaction
    )

    current := Array()
    for (acdcindex, acdc in acdcs) {
        current.Push(RegRead(regpath, acdc . "SettingIndex"))
        if (current[acdcindex] < 0 or 3 < current[acdcindex]) {
            MsgBox(acdc . "SettingIndex out of range")
            ExitApp()
        }
    }
    current.Push(current[1] = current[2] ? current[1] : -1)
    return current
}

; on tray icon events
showmenu(guids, wparam, lparam, *) {
    global triggers, m

    if (lparam = 0x203) { ; double-click
        opengui(guids)
        return 1 ; consumed
    }
    else if ( not triggers.Has(lparam)) {
        return 0 ; ignored
    }

    current := getcurvalues(guids)

    mymenu := Menu()
    for (acdcindex, acdc in m.acdcs) {
        for (actionindex, action in m.actions) {
            itemname := Format("{} {}", acdc, action)
            mymenu.Add(
                itemname
                , applysettings.Bind({
                    ; bitwise-and for the "both" (acdcindex=3) case
                    AC: acdcindex & 1 ? actionindex : 0
                    , DC: acdcindex & 2 ? actionindex : 0
                }
                    , guids
                )
                , actionindex = 1 ? "Break" : ""
            )
            if (actionindex = current[acdcindex] + 1) {
                mymenu.Check(itemname)
            }
        }
        mymenu.Add()
        switch (acdcindex) {
            case (1): mymenu.Add(m.progname, (*) => true), mymenu.Disable(m.progname)
            case (2): mymenu.Add(m.exit, (*) => ExitApp())
            case (3): mymenu.Add(m.opengui, (*) => opengui(guids)), mymenu.Default := m.opengui
        }
    }

    mymenu.Show()
    return 1 ; consumed
}

; can be called from menu, so the last parameter is a star
applysettings(gvalues, guids, *) {
    global acdcs

    cmd := "cmd.exe /c "
    for (acdcindex, acdc in acdcs) {
        if (gvalues.%acdc%) {
            cmd .= Format(
                "powercfg /set{}valueindex {} {} {} {} && "
                , acdc
                , guids.scheme_current
                , guids.sub_buttons
                , guids.lidaction
                , gvalues.%acdc% -1
            )
        }
    }
    cmd .= "powercfg /setactive " . guids.scheme_current

    result := StdoutToVar(cmd)
    if (result.ExitCode) {
        MsgBox(Format(
            "powercfg failed: {}`r`n{}"
            , result.ExitCode
            , result.Output
        ))
    }
}

opengui(guids) {
    global m

    mygui := Gui(, m.progname)
    radiogroups := addradiogroups(mygui)
    checkradio(radiogroups, guids, &curvalues)
    addbuttons(mygui, guids, radiogroups, &curvalues)
    mygui.Show()
}

addradiogroups(mygui) {
    global acdcs, m

    groups := []
    for (acdcindex, acdc in acdcs) {
        mygui.AddText("ym w110", m.acdcs[acdcindex])
        groups.Push([])
        for (actionindex, action in m.actions) {
            groups[acdcindex].Push(
                mygui.AddRadio(
                    "r1.5" . (actionindex = 1 ? " Group v" . acdc : "")
                    , action
                )
            )
        }
    }
    return groups
}

; update curvalues and check radio accordingly
checkradio(radiogroups, guids, &current) {
    global acdcs
    current := getcurvalues(guids)

    for (acdcindex, acdc in acdcs) {
        radiogroups[acdcindex][current[acdcindex] + 1].Value := 1
    }
}

; attach fat-arrow funcs to click events
addbuttons(mygui, guids, radiogroups, &current) {
    global m

    mygui.AddButton("x80 w80", m.apply)
        .OnEvent("Click", (*) => (
            applysettings(mygui.Submit(false), guids)
            , checkradio(radiogroups, guids, &current)
        ))
    mygui.AddButton("xp+90 w80", m.ok)
        .OnEvent("Click", (*) => (
            applysettings(mygui.Submit(false), guids)
            , mygui.Destroy()
        ))
}