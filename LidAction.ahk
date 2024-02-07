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
m := IsSet(m) ? m : messages.en
; events on which the tray icon shows the menu
triggers := IsSet(triggers) ? triggers : Map(
    0x205, "right click"
    ; , 0x200, "hover"
    ; , 0x202, "click - will disable double-click action"
)

; global variable
acdcs := ["AC", "DC"]

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
    powercfg := StdoutToVar("powercfg /query " . args)
    if (powercfg.ExitCode) {
        MsgBox("powercfg failed:`r`n" . powercfg.Output)
        ExitApp()
    }
    lines := StrSplit(powercfg.Output, "`n", " `r")
    if (lines.Length < min) {
        MsgBox("powercfg incompatible:`r`n" . powercfg.Output)
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

; returns an array-like map (1: ACValue, 2: DCValue, 3: BothValue or -1, guid*: guid)
; admin priv is not needed here
getcurvalues(guid1, guid2, guid3, max := 0xffffffff) {
    global acdcs

    regpath := Format(
        "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\{}\{}\{}"
        ,guid1, guid2, guid3
    )

    current := Map(
        "guid1", guid1
        , "guid2", guid2
        , "guid3", guid3
    )
    for (acdcindex, acdc in acdcs) {
        regval := RegRead(regpath, acdc . "SettingIndex", "NOENTRY")
        if (regval = "NOENTRY") {
            return regval
        }
        if (regval < 0 or max < regval) {
            MsgBox(
                Format(
                    "{}SettingIndex out of range: {}`r`n{}/{}/{}"
                    , acdc, regval, guid1, guid2, guid3
                )
            )
            ExitApp()
        }
        current[acdcindex] := regval
    }
    current[3] := (current[1] = current[2] ? current[1] : -1)
    return current
}

; on tray icon events
showmenu(wparam, lparam, *) {
    global triggers, acdcs, m

    if (lparam = 0x203) { ; double-click
        opengui()
        return 1 ; consumed
    }
    else if ( not triggers.Has(lparam)) {
        return 0 ; ignored
    }

    guids := getguids()
    curlid := getcurvalues(guids.scheme_current, guids.sub_buttons, guids.lidaction, 3)
    curvideo := getcurvalues(guids.scheme_current, guids.sub_video, guids.videoidle)
    curstand := getcurvalues(guids.scheme_current, guids.sub_sleep, guids.standbyidle)
    curhiber := getcurvalues(guids.scheme_current, guids.sub_sleep, guids.hibernateidle)

    mymenu := Menu()
    acdcboth := acdcs.Clone()
    acdcboth.Push("Both")
    for (acdcindex, acdc in acdcboth) {
        if (acdcindex < 3) {
            mymenu.Add(
                idlename(m.videoidle, m.acdcs[acdcindex], curvideo[acdcindex])
                , idlemenu(acdc, curvideo)
                , "Break"
            )
            mymenu.Add(
                idlename(m.standbyidle, m.acdcs[acdcindex], curstand[acdcindex])
                , idlemenu(acdc, curstand)
            )
            mymenu.Add(
                idlename(m.hibernateidle, m.acdcs[acdcindex], curhiber[acdcindex])
                , idlemenu(acdc, curhiber)
            )
        } else {
            mymenu.Add(m.exit, (*) => ExitApp(), "Break")
            mymenu.Add(m.allnever, (*) => disableall([curlid, curvideo, curstand, curhiber]))
            mymenu.Add(m.progname, (*) => opengui()), mymenu.Default := m.progname
        }
        if (curlid = "NOENTRY") {
            continue
        }
        mymenu.Add()
        for (actionindex, action in m.actions) {
            itemname := Format("{} {}", m.acdcs[acdcindex], action)
            mymenu.Add(
                itemname
                , applyacdc.Bind(
                    {
                        ; bitwise-and for the "both" (acdcindex=3) case
                        AC: (acdcindex & 1 ? actionindex : 0) -1
                        , DC: (acdcindex & 2 ? actionindex : 0) -1
                    }
                    , curlid
                )
            )
            if (actionindex = curlid[acdcindex] + 1) {
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

idlemenu(acdc, current) {
    global m

    submenu := Menu()
    lens := [[m.never, 0]]
    for (minute in [1, 2, 3, 5, 10, 15, 20, 25, 30, 45]) {
        lens.Push([Format(m.minutesfmt, minute), minute * 60])
    }
    for (hour in [1, 2, 3, 4, 5]) {
        lens.Push([Format(m.hoursfmt, hour), hour * 3600])
    }
    for (len in lens) {
        submenu.Add(len[1], applysetting.Bind(
            acdc, current, len[2]
        ))
    }
    return submenu
}

disableall(all) {
    for (c in all) {
        applyacdc({AC: 0, DC: 0}, c)
    }
}

; can be called from menu, so the last parameter is a star
applyacdc(gvalues, cvmap, *) {
    global acdcs

    if (cvmap = "NOENTRY") {
        return
    }
    for (acdcindex, acdc in acdcs) {
        if (gvalues.%(acdc)% >= 0) {
            applysetting(acdc, cvmap, gvalues.%(acdc)%)
        }
    }
}

applysetting(acdc, cvmap, value, *) {
    cmd := Format(
        "cmd.exe /c powercfg /set{}valueindex {} {} {} {}"
        , acdc, cvmap["guid1"], cvmap["guid2"], cvmap["guid3"], value
    )
    setactive(cmd, cvmap["guid1"])
}

setactive(cmd, scheme) {
    cmd .= " && powercfg /setactive " . scheme
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
    global m

    guids := getguids()

    mygui := Gui(, m.progname)
    radiogroups := addradiogroups(mygui)

    updategui(radiogroups, guids, &curlid, &curvideo, &curstand, &curhiber)

    mygui.AddButton("x200 y+40 w80", m.apply)
        .OnEvent("Click", (*) => (
            gvalues := mygui.Submit(false)
            , gvalues.AC--, gvalues.DC--
            , applyacdc(gvalues, curlid)
            , applyupdowns(gvalues, curvideo, "video")
            , applyupdowns(gvalues, curstand, "stand")
            , applyupdowns(gvalues, curhiber, "hiber")
            , updategui(radiogroups, guids, &curlid, &curvideo, &curstand, &curhiber)
        ))
    mygui.AddButton("yp w80", m.ok)
        .OnEvent("Click", (*) => (
            gvalues := mygui.Submit(false)
            , gvalues.AC--, gvalues.DC--
            , applyacdc(gvalues, curlid)
            , applyupdowns(gvalues, curvideo, "video")
            , applyupdowns(gvalues, curstand, "stand")
            , applyupdowns(gvalues, curhiber, "hiber")
            , mygui.Destroy()
        ))
    mygui.Show()
}

applyupdowns(gvalues, cvmap, cvname) {
    global acdcs

    data := {}
    for (acdcindex, acdc in acdcs) {
        s := 0
        for (dhm, multi in Map(
            "d", 24 * 60 * 60
            , "h", 60 * 60
            , "m", 60
        )) {
            s += gvalues.%(acdc)%%(cvname)%%(dhm)% * multi
        }
        applysetting(acdc, cvmap, s)
    }
}

addradiogroups(mygui) {
    global acdcs, m

    groups := []
    lens := {}
    for (acdcindex, acdc in acdcs) {
        top := mygui.AddText("ym w280 center", m.acdcs[acdcindex])
        top.GetPos(&x, &y, &w, &h)
        groups.Push([])
        for (actionindex, action in m.actions) {
            groups[acdcindex].Push(
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
                case 2: addedit(mygui, x + 80, lens, acdc, "stand")
                case 3: addedit(mygui, x + 80, lens, acdc, "hiber")
            }
        }
        mygui.AddText("xp y+30", m.vidoff)
        addedit(mygui, x + 80, lens, acdc, "video")
    }
    groups.Push(lens)
    return groups
}

addedit(mygui, x, idles, acdc, cvname) {
    global m

    mygui.AddEdit(Format("yp x{} w40 right", x))
    idles.%(acdc)%%(cvname)%d := mygui.AddUpDown(Format("left range0-99 v{}{}d", acdc, cvname))
    mygui.AddText("yp", m.days)

    mygui.AddEdit("yp w40 right")
    idles.%(acdc)%%(cvname)%h := mygui.AddUpDown(Format("left range0-23 v{}{}h", acdc, cvname))
    mygui.AddText("yp", m.hours)

    mygui.AddEdit("yp w40 right")
    idles.%(acdc)%%(cvname)%m := mygui.AddUpDown(Format("left range0-59 v{}{}m", acdc, cvname))
    mygui.AddText("yp", m.minutes)
}

; updates curvalues, checks radios and inputs edits accordingly
updategui(radiogroups, guids, &curlid, &curvideo, &curstand, &curhiber) {
    global acdcs

    curlid := getcurvalues(guids.scheme_current, guids.sub_buttons, guids.lidaction, 3)
    curvideo := getcurvalues(guids.scheme_current, guids.sub_video, guids.videoidle)
    curstand := getcurvalues(guids.scheme_current, guids.sub_sleep, guids.standbyidle)
    curhiber := getcurvalues(guids.scheme_current, guids.sub_sleep, guids.hibernateidle)
    o := radiogroups[3]

    for (acdcindex, acdc in acdcs) {
        for (cvname in ["video", "stand", "hiber"]) {
            dhm := getdhm(cur%(cvname)%[acdcindex])
            o.%(acdc)%%(cvname)%d.Value := dhm.d
            o.%(acdc)%%(cvname)%h.Value := dhm.h
            o.%(acdc)%%(cvname)%m.Value := dhm.m
        }
        for (actionindex, action in m.actions) {
            radiogroups[acdcindex][actionindex].Value := 0
        }
        if (curlid = "NOENTRY") {
            for (actionindex, action in m.actions) {
                radiogroups[acdcindex][actionindex].Enabled := false
            }
            continue
        }
        radiogroups[acdcindex][curlid[acdcindex] + 1].Value := 1
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
