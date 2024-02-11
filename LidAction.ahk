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

acdcs := ["AC", "DC"]
acdcboths := acdcs.Clone()
acdcboths.Push("Both")
#Include PowercfgGUIDs.ahk
guids := PowercfgGUIDs()

class PowerValues {
    __New(guids) {
        this.guid1 := guids.guid1
        this.guid2 := guids.guid2
        this.guid3 := guids.guid3
        this.max := guids.max
    }

    ; admin priv is not needed here
    update() {
        regpath := Format(
            "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\{}\{}\{}"
            ,this.guid1, this.guid2, this.guid3
        )

        for (acdcindex, acdc in acdcs) {
            regval := RegRead(regpath, acdc . "SettingIndex", "NOENTRY")
            if (regval = "NOENTRY") {
                return false
            }
            if (regval < 0 or this.max < regval) {
                MsgBox(
                    Format(
                        "{}SettingIndex out of range: {}`r`n{}/{}/{}"
                        , acdc, regval, this.guid1, this.guid2, this.guid3
                    )
                )
                ExitApp()
            }
            this.%(acdc)% := regval
        }
        this.Both := (this.AC = this.DC) ? this.AC : -1
        return
    }

    ; can be called from menu, so the last parameter is a star
    applyacdc(gvalues, *) {
        for (acdcindex, acdc in acdcs) {
            val := -1
            if (gvalues.HasOwnProp(acdc)) {
                val := gvalues.%(acdc)%
            } else if (gvalues.HasOwnProp("Both")) {
                val := gvalues.Both
            }
            if (val >= 0) {
                this.apply(acdc, val)
            }
        }
    }

    ; can be called from menu, so the last parameter is a star
    apply(acdc, value, *) {
        cmd := Format(
            "cmd.exe /c powercfg /set{}valueindex {} {} {} {}"
            , acdc, this.guid1, this.guid2, this.guid3, value
        )
        cmd .= " && powercfg /setactive " . this.guid1
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
}

class PowerObjs {
    __New() {
        this.entries := ["lid", "video", "stand", "hiber"]
        this.dhmentries := ["video", "stand", "hiber"]
        for (k in this.entries) {
            this.%(k)% := PowerValues(guids.%(k)%)
        }
    }

    disableall() {
        for (c in this.entries) {
            this.%(c)%.applyacdc({Both: 0})
        }
    }
}


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



; on tray icon events
showmenu(wparam, lparam, *) {
    if (lparam = 0x203) { ; double-click
        opengui()
        return 1 ; consumed
    }
    else if ( not triggers.Has(lparam)) {
        return 0 ; ignored
    }

    idleobjs := PowerObjs()
    for (cvname in idleobjs.entries.Clone()) {
        if (idleobjs.%(cvname)%.update() = false) {
            removefromarray(idleobjs.entries, cvname)
            idleobjs.DeleteProp(cvname)
        }
    }

    mymenu := Menu()
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
            mymenu.Add(m.allnever, (*) => idleobjs.disableall())
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
                , ObjBindMethod(idleobjs.lid, "applyacdc", {%(acdc)%: actionindex - 1})
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
        submenu.Add(len.name, ObjBindMethod(cv, "apply", acdc, len.sec))
    }
    return submenu
}

opengui() {
    mygui := Gui(, m.progname)
    radiogroups := addradiogroups(mygui)

    idleobjs := PowerObjs()
    updategui(radiogroups, idleobjs)

    mygui.AddButton("x200 y+40 w80", m.apply)
        .OnEvent("Click", (*) => (
            gvalues := mygui.Submit(false)
            , gvalues.AC--, gvalues.DC--
            , idleobjs.HasOwnProp("lid") && idleobjs.lid.applyacdc(gvalues)
            , applyupdowns(gvalues, idleobjs)
            , updategui(radiogroups, idleobjs)
        ))
    mygui.AddButton("yp w80", m.ok)
        .OnEvent("Click", (*) => (
            gvalues := mygui.Submit(false)
            , gvalues.AC--, gvalues.DC--
            , idleobjs.HasOwnProp("lid") && idleobjs.lid.applyacdc(gvalues)
            , applyupdowns(gvalues, idleobjs)
            , mygui.Destroy()
        ))
    mygui.Show()
}

applyupdowns(gvalues, idleobjs) {
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
            idleobjs.%(cvname)%.apply(acdc, s)
        }
    }
}

addradiogroups(mygui) {
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
updategui(radiogroups, idleobjs) {
    for (cvname in idleobjs.entries.Clone()) {
        if (idleobjs.%(cvname)%.update() = false) {
            removefromarray(idleobjs.entries, cvname)
            idleobjs.DeleteProp(cvname)
        }
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

removefromarray(arr, val) {
    for (i, v in arr) {
        if (v = val) {
            arr.RemoveAt(i)
            break
        }
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
