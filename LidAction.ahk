#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

; https://www.autohotkey.com/boards/viewtopic.php?p=485503#p485503
#Include StdoutToVar.ahk

plans := ["AC", "DC", "Both"]
actions := ["Nothing", "Sleep", "Hibernate", "Shutdown"]
guids := getguids()

TraySetIcon("shell32.dll", -284)
; the first character of the filename decides how it works
; !G will stay in the tray (useful for startup)
if (StrUpper(SubStr(A_ScriptName, 1, 1) != "G")) {
    OnMessage(0x404, showmenu.Bind(guids)) ; tray icon
    Persistent()
    return
}
; if the filename starts with G, show one-time GUI
opengui(guids)
return


; returns an object
; note that powercfg messages are localized
getguids() {
    spcfg := StdoutToVar("powercfg /query scheme_current sub_buttons")
    if (spcfg.ExitCode) {
        MsgBox("powercfg failed:`r`n" . spcfg.Output)
        ExitApp()
    }
    apcfg := StrSplit(spcfg.Output, "`n", " `r")
    if (apcfg.Length < 4) {
        MsgBox("powercfg incompatible:`r`n" . spcfg.Output)
        ExitApp()
    }

    guidregex := " ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) "
    if ( not RegExMatch(apcfg[1], guidregex, &scheme_current)) {
        MsgBox("scheme_current not found:`r`n" . apcfg[1])
        ExitApp()
    }
    if ( not RegExMatch(apcfg[3], guidregex, &sub_buttons)) {
        MsgBox("sub_buttons not found:`r`n" . apcfg[3])
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
    global plans

    regpath := Format(
        "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\{}\{}\{}",
        guids.scheme_current,
        guids.sub_buttons,
        guids.lidaction
    )

    current := Array()
    for (planindex, plan in plans) {
        if (planindex < 3) {
            current.Push(RegRead(regpath, plan . "SettingIndex"))
            if (current[planindex] < 0 or 3 < current[planindex]) {
                MsgBox(plan . "SettingIndex out of range")
                ExitApp()
            }
        }
        else {
            current.Push(current[1] = current[2] ? current[1] : -1)
        }
    }
    return current
}

; on tray icon events
showmenu(guids, wparam, lparam, *) {
    global plans, actions

    if (lparam = 0x203) { ; double-click
        opengui(guids)
        return 1 ; consumed
    }
    else if (lparam != 0x205) { ; right-click
        return 0 ; ignored
    }

    current := getcurvalues(guids)

    mymenu := Menu()
    for (planindex, plan in plans) {
        for (actionindex, action in actions) {
            itemname := Format("{} {}", planname(planindex), action)
            mymenu.Add(
                itemname
                , applysettings.Bind(
                    { ; bitwise-and for the "both" (planindex=3) case
                        AC: planindex & 1 ? actionindex : 0
                        , DC: planindex & 2 ? actionindex : 0
                    }
                    , guids
                )
                , actionindex = 1 ? "Break" : ""
            )
            if (actionindex = current[planindex] + 1) {
                mymenu.Check(itemname)
            }
        }
        mymenu.Add()
        switch(planindex) {
            case(2): mymenu.Add("Exit", (*) => ExitApp())
            case(3): mymenu.Add("Open GUI", (*) => opengui(guids))
        }
    }
    mymenu.Default := "Open GUI"
    mymenu.Show()
    return 1 ; consumed
}

; append emoji
planname(planindex) {
    global plans

    return plans[planindex] . (
        planindex = 1 ? "⚡" : (
            planindex = 2 ? "🔋" : ""
        )
    )
}

; can be called from menu, so the last parameter is a star
applysettings(gvalues, guids, *) {
    global plans

    cmd := "cmd.exe /c "
    for (planindex, plan in plans) {
        if (planindex > 2) {
            break
        }
        if (gvalues.%plan%) {
            cmd .= Format(
                "powercfg /set{}valueindex {} {} {} {} && "
                , plan
                , guids.scheme_current
                , guids.sub_buttons
                , guids.lidaction
                , gvalues.%plan% -1
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
    mygui := Gui()
    radiogroups := addradiogroups(mygui)
    checkradio(radiogroups, guids, &curvalues)
    addbuttons(mygui, guids, radiogroups, &curvalues)
    mygui.Show()
}

addradiogroups(mygui) {
    global plans, actions

    groups := []
    for (planindex, plan in plans) {
        if (planindex > 2) {
            break
        }
        mygui.AddText("ym w110", planname(planindex))
        groups.Push([])
        for (actionindex, action in actions) {
            groups[planindex].Push(
                mygui.AddRadio(
                    "r1.5" . (actionindex = 1 ? " Group v" . plan : "")
                    , action
                )
            )
        }
    }
    return groups
}

; update curvalues and check radio accordingly
checkradio(radiogroups, guids, &current) {
    global plans
    current := getcurvalues(guids)

    for (planindex, plan in plans) {
        if (planindex > 2) {
            break
        }
        radiogroups[planindex][current[planindex] + 1].Value := 1
    }
}

; attach fat-arrow funcs to click events
addbuttons(mygui, guids, radiogroups, &current) {
    mygui.AddButton("x80 w80", "Apply")
        .OnEvent("Click", (*) => (
            applysettings(mygui.Submit(false), guids)
            , checkradio(radiogroups, guids, &current)
        )
    )
    mygui.AddButton("xp+90 w80", "OK")
        .OnEvent("Click", (*) => (
            applysettings(mygui.Submit(false), guids)
            , mygui.Destroy()
        )
    )
}