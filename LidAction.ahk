#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn

;@Ahk2Exe-SetName        LidAction.ahk
;@Ahk2Exe-SetVersion     0.2.1
;@Ahk2Exe-SetDescription LidAction.ahk - powercfg wrapper

; https://www.autohotkey.com/boards/viewtopic.php?p=485503#p485503
#Include StdoutToVar.ahk
; translatable messages
#Include LidActionMsg.ahk
; this is used as other icons too
TraySetIcon("shell32.dll", -284)

#Include LidActionCfg.ahk
m := m ?? messages.en
; events on which the tray icon shows the menu
triggers := triggers ?? Map(
    0x205, "right click"
    ; , 0x200, "hover"
    ; , 0x202, "click - will disable double-click action"
)

; global variables
acdcs := ["AC", "DC"]
guids := getguids()

; the first character of the filename decides how it works
; !G will stay in the tray (useful for startup)
if (StrUpper(SubStr(A_ScriptName, 1, 1) != "G")) {
    A_IconTip := m.progname
    OnMessage(0x404, showmenu) ; tray icon
    Persistent()
    return
}
; if the filename starts with G, show one-time GUI
; without a tray icon
A_IconHidden := true
opengui()
return


; returns an object
; note that powercfg messages are localized
getguids() {
    buttonslines := getpcqlines("scheme_current sub_buttons", 4)
    videolines := getpcqlines("scheme_current sub_video videoidle", 12)
    sleeplines := getpcqlines("scheme_current sub_sleep standbyidle", 12)
    hibernatelines := getpcqlines("scheme_current sub_sleep hibernateidle", 12)

    ; https://learn.microsoft.com/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action
    lidaction := "5ca83367-6e45-459f-a27b-476b1d01c936" ; not available from powercfg

    return {
        scheme_current: getguid(buttonslines[1])
        , sub_buttons: getguid(buttonslines[3])
        , lidaction: lidaction
        , sub_video: getguid(videolines[3])
        , videoidle: getguid(videolines[5])
        , sub_sleep: getguid(sleeplines[3])
        , standbyidle: getguid(sleeplines[5])
        , hibernateidle: getguid(hibernatelines[5])
    }
}

getpcqlines(args, min) {
    cmd := "powercfg /query " . args
    powercfg := StdoutToVar(cmd)
    if (powercfg.ExitCode) {
        MsgBox(cmd . " failed:`r`n" . powercfg.Output)
        ExitApp()
    }
    lines := StrSplit(powercfg.Output, "`n", " `r")
    if (lines.Length < min) {
        MsgBox(cmd . " incompatible:`r`n" . powercfg.Output)
        ExitApp()
    }
    return lines
}

getguid(line) {
    static guidregex := " ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) "

    if ( not RegExMatch(line, guidregex, &guid)) {
        MsgBox("guid not found:`r`n" . line)
        ExitApp()
    }
    return guid[1]
}

; updates idleobjs.%cvname% {AC, DC, Both, guid1, guid2, guid3}
; admin priv is not needed here
updatecurrentvalue(idleobjs, cvname) {
    global acdcs

    cv := idleobjs.%(cvname)%
    regpath := Format(
        "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\{}\{}\{}"
        ,cv.guid1, cv.guid2, cv.guid3
    )

    for (acdcindex, acdc in acdcs) {
        regval := RegRead(regpath, acdc . "SettingIndex", "NOENTRY")
        if (regval = "NOENTRY") {
            removefromarray(idleobjs.entries, cvname)
            idleobjs.DeleteProp(cvname)
            return
        }
        if (regval < 0 or cv.max < regval) {
            MsgBox(
                Format(
                    "{} {}SettingIndex out of range: {}`r`n{}/{}/{}"
                    , cvname, acdc, regval, cv.guid1, cv.guid2, cv.guid3
                )
            )
            ExitApp()
        }
        cv.%(acdc)% := regval
    }
    cv.Both := (cv.AC = cv.DC) ? cv.AC : -1
    return
}

initidles() {
    return {
        entries: ["lid", "video", "stand", "hiber"]
        , lid: {
            guid1: guids.scheme_current
            , guid2: guids.sub_buttons
            , guid3: guids.lidaction
            , max: 3
        }
        , dhmentries: ["video", "stand", "hiber"]
        , video: {
            guid1: guids.scheme_current
            , guid2: guids.sub_video
            , guid3: guids.videoidle
            , max: 0xffffffff
        }
        , stand: {
            guid1: guids.scheme_current
            , guid2: guids.sub_sleep
            , guid3: guids.standbyidle
            , max: 0xffffffff
        }
        , hiber: {
            guid1: guids.scheme_current
            , guid2: guids.sub_sleep
            , guid3: guids.hibernateidle
            , max: 0xffffffff
        }
    }
}

removefromarray(arr, val) {
    for (i, v in arr) {
        if (v = val) {
            arr.RemoveAt(i)
            break
        }
    }
}

; on tray icon events
showmenu(wparam, lparam, *) {
    global m, triggers, acdcs

    if (lparam = 0x203) { ; double-click
        opengui()
        return 1 ; consumed
    }
    else if ( not triggers.Has(lparam)) {
        return 0 ; ignored
    }

    idleobjs := initidles()
    for (cvname in idleobjs.entries.Clone()) {
        updatecurrentvalue(idleobjs, cvname)
    }

    mymenu := Menu()
    acdcboths := acdcs.Clone()
    acdcboths.Push("Both")
    for (acdcindex, acdc in acdcboths) {
        if (acdcindex <= acdcs.Length) {
            for (cvindex, cvname in idleobjs.dhmentries) {
                mymenu.Add(
                    idlename(m.%(cvname)%idlefmt, m.acdcs[acdcindex], idleobjs.%(cvname)%.%(acdc)%)
                    , idlemenu(acdc, idleobjs.%(cvname)%)
                    , cvindex = 1 ? "Break" : ""
                )
            }
        } else {
            mymenu.Add(m.exit, (*) => ExitApp(), "Break")
            mymenu.Add(m.allnever, (*) => disableall(idleobjs))
            mymenu.Add(m.progname, (*) => opengui()), mymenu.Default := m.progname
        }

        if ( not idleobjs.HasOwnProp("lid")) {
            continue
        }
        mymenu.Add()
        for (actionindex, action in m.actions) {
            itemname := Format("{} {}", m.acdcs[acdcindex], action)
            mymenu.Add(
                itemname
                , applyacdc.Bind(
                    {
                        AC: ((acdc = "AC" or acdc = "Both") ? actionindex : 0) - 1
                        , DC: ((acdc = "DC" or acdc = "Both") ? actionindex : 0) - 1
                    }
                    , idleobjs.lid
                )
            )
            if (actionindex = idleobjs.lid.%(acdc)% + 1) {
                mymenu.Check(itemname)
            }
        }
    }

    mymenu.Show()
    return 1 ; consumed
}

idlename(fmt, acdc, sec) {
    return Format(fmt, acdc, Floor(sec / 3600), Round(Mod(sec, 3600) / 60))
}

idlemenu(acdc, cv) {
    global m

    submenu := Menu()
    lenitems := [{name: m.never, sec: 0}]
    for (minute in [1, 2, 3, 5, 10, 15, 20, 25, 30, 45]) {
        lenitems.Push(
            {
                name: Format(m.minutesfmt, minute)
                , sec: minute * 60
            }
        )
    }
    for (hour in [1, 2, 3, 4, 5]) {
        lenitems.Push(
            {
                name: Format(m.hoursfmt, hour)
                , sec: hour * 3600
            }
        )
    }

    for (len in lenitems) {
        submenu.Add(len.name, applysetting.Bind(
            acdc, cv, len.sec
        ))
    }
    return submenu
}

disableall(idleobjs) {
    for (c in idleobjs.entries) {
        applyacdc({AC: 0, DC: 0}, idleobjs.%(c)%)
    }
}

; can be called from menu, so the last parameter is a star
applyacdc(gvalues, cv, *) {
    global acdcs

    for (acdcindex, acdc in acdcs) {
        if (gvalues.%(acdc)% >= 0) {
            applysetting(acdc, cv, gvalues.%(acdc)%)
        }
    }
}

applysetting(acdc, cv, value, *) {
    cmd := Format(
        "cmd.exe /c powercfg /set{}valueindex {} {} {} {}"
        , acdc, cv.guid1, cv.guid2, cv.guid3, value
    )
    cmd .= " && powercfg /setactive " . cv.guid1
    result := StdoutToVar(cmd)
    if (result.ExitCode) {
        MsgBox(Format(
            "powercfg failed: {}`r`n{}`r`n`r`n{}"
            , result.ExitCode
            , cmd
            , result.Output
        ))
    }
}

opengui() {
    global m, guids

    mygui := Gui(, m.progname)
    radiogroups := addradiogroups(mygui)

    idleobjs := initidles()
    updategui(radiogroups, guids, idleobjs)

    mygui.AddButton("x200 y+40 w80", m.apply)
        .OnEvent("Click", (*) => (
            gvalues := mygui.Submit(false)
            , gvalues.AC--, gvalues.DC--
            , idleobjs.HasOwnProp("lid") && applyacdc(gvalues, idleobjs.lid)
            , applyupdowns(gvalues, idleobjs)
            , updategui(radiogroups, guids, idleobjs)
        ))
    mygui.AddButton("yp w80", m.ok)
        .OnEvent("Click", (*) => (
            gvalues := mygui.Submit(false)
            , gvalues.AC--, gvalues.DC--
            , idleobjs.HasOwnProp("lid") && applyacdc(gvalues, idleobjs.lid)
            , applyupdowns(gvalues, idleobjs)
            , mygui.Destroy()
        ))
    mygui.Show()
}

applyupdowns(gvalues, idleobjs) {
    global acdcs

    for (cvname in idleobjs.dhmentries) {
        for (acdcindex, acdc in acdcs) {
            s := 0
            for (dhm, multi in Map(
                "d", 24 * 60 * 60
                , "h", 60 * 60
                , "m", 60
            )) {
                s += gvalues.%(acdc)%%(cvname)%%(dhm)% * multi
            }
            applysetting(acdc, idleobjs.%(cvname)%, s)
        }
    }
}

addradiogroups(mygui) {
    global m, acdcs

    groups := {}
    dhms := {}
    for (acdcindex, acdc in acdcs) {
        top := mygui.AddText("ym w280 center", m.acdcs[acdcindex])
        top.GetPos(&x, &y, &w, &h)
        groups.%(acdc)% := []
        for (actionindex, action in m.actions) {
            groups.%(acdc)%.Push(
                mygui.AddRadio(
                    Format(
                        "x{} y{} r1.5 {}"
                        , x
                        , y + (h * 1.5 + mygui.MarginY) * actionindex
                        , actionindex = 1 ? " Group v" . acdc : ""
                    )
                    , action
                )
            )
            switch (actionindex) {
                case 2: addedit(mygui, x + 80, dhms, acdc, "stand")
                case 3: addedit(mygui, x + 80, dhms, acdc, "hiber")
            }
        }
        mygui.AddText("xp y+30", m.vidoff)
        addedit(mygui, x + 80, dhms, acdc, "video")
    }
    groups.dhms := dhms
    return groups
}

addedit(mygui, x, dhms, acdc, cvname) {
    global m

    mygui.AddEdit(Format("yp x{} w40 right", x))
    dhms.%(acdc)%%(cvname)%d := mygui.AddUpDown(Format("left range0-99 v{}{}d", acdc, cvname))
    mygui.AddText("yp", m.days)

    mygui.AddEdit("yp w40 right")
    dhms.%(acdc)%%(cvname)%h := mygui.AddUpDown(Format("left range0-23 v{}{}h", acdc, cvname))
    mygui.AddText("yp", m.hours)

    mygui.AddEdit("yp w40 right")
    dhms.%(acdc)%%(cvname)%m := mygui.AddUpDown(Format("left range0-59 v{}{}m", acdc, cvname))
    mygui.AddText("yp", m.minutes)
}

; updates idleobjs, checks radios, and inputs edits accordingly
updategui(radiogroups, guids, idleobjs) {
    global acdcs

    for (cvname in idleobjs.entries.Clone()) {
        updatecurrentvalue(idleobjs, cvname)
    }

    for (acdcindex, acdc in acdcs) {
        for (cvname in idleobjs.dhmentries) {
            dhm := getdhm(idleobjs.%(cvname)%.%(acdc)%)
            radiogroups.dhms.%(acdc)%%(cvname)%d.Value := dhm.d
            radiogroups.dhms.%(acdc)%%(cvname)%h.Value := dhm.h
            radiogroups.dhms.%(acdc)%%(cvname)%m.Value := dhm.m
        }
        for (actionindex, action in m.actions) {
            radiogroups.%(acdc)%[actionindex].Value := 0
        }
        if ( not idleobjs.HasOwnProp("lid")) {
            for (actionindex, action in m.actions) {
                radiogroups.%(acdc)%[actionindex].Enabled := false
            }
            continue
        }
        radiogroups.%(acdc)%[idleobjs.lid.%(acdc)% + 1].Value := 1
    }
}

getdhm(secs) {
    days := Floor(secs / (24 * 60 * 60))
    secs -= days * (24 * 60 * 60)
    hours := Floor(secs / (60 * 60))
    secs -= hours * (60 * 60)
    minutes := Round(secs / 60)
    return {
        d: days
        , h: hours
        , m: minutes
    }
}
