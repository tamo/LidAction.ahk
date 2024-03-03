#Requires AutoHotkey v2.0

class PowercfgGUIDs {
    __New() {
        buttonslines := this.getpcqlines("scheme_current sub_buttons", 4)
        scheme_current := this.getguid(buttonslines[1])
        this.lid := {
            guid1: scheme_current
            , guid2: "4f971e89-eebd-4455-a8de-9e59040e7347"
            , guid3: "5ca83367-6e45-459f-a27b-476b1d01c936"
            , max: 3
        }
        this.video := {
            guid1: scheme_current
            , guid2: "7516b95f-f776-4464-8c53-06167f40cc99"
            , guid3: "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e"
            , max: 0xffffffff
        }
        sub_sleep := "238c9fa8-0aad-41ed-83f4-97be242c8f20"
        this.stand := {
            guid1: scheme_current
            , guid2: sub_sleep
            , guid3: "29f6c1db-86da-48c5-9fdb-f2b67b1f44da"
            , max: 0xffffffff
        }
        this.hiber := {
            guid1: scheme_current
            , guid2: sub_sleep
            , guid3: "9d7815a6-7ee4-497e-8888-515a05f02364"
            , max: 0xffffffff
        }
    }

    renew() {
        buttonslines := this.getpcqlines("scheme_current sub_buttons", 4)
        scheme_current := this.getguid(buttonslines[1])
        ; some schemes have no alias
        current_has_alias := RegExMatch(buttonslines[2], " SCHEME_[A-Z]") ? 1 : 0
        sub_buttons := this.getguid(buttonslines[2 + current_has_alias])
        ; https://learn.microsoft.com/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action
        lidaction := "5ca83367-6e45-459f-a27b-476b1d01c936" ; not available from powercfg

        this.lid := {
            guid1: scheme_current
            , guid2: sub_buttons
            , guid3: lidaction
            , max: 3
        }

        videolines := this.getpcqlines("scheme_current sub_video videoidle", 12)
        sub_video := this.getguid(videolines[2 + current_has_alias])
        videoidle := this.getguid(videolines[4 + current_has_alias])

        this.video := {
            guid1: scheme_current
            , guid2: sub_video
            , guid3: videoidle
            , max: 0xffffffff
        }

        sleeplines := this.getpcqlines("scheme_current sub_sleep standbyidle", 12)
        sub_sleep := this.getguid(sleeplines[2 + current_has_alias])
        standbyidle := this.getguid(sleeplines[4 + current_has_alias])

        this.stand := {
            guid1: scheme_current
            , guid2: sub_sleep
            , guid3: standbyidle
            , max: 0xffffffff
        }

        hibernatelines := this.getpcqlines("scheme_current sub_sleep hibernateidle", 12)
        hibernateidle := this.getguid(hibernatelines[4 + current_has_alias])

        this.hiber := {
            guid1: scheme_current
            , guid2: sub_sleep
            , guid3: hibernateidle
            , max: 0xffffffff
        }
    }

    ; note that powercfg messages are localized
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
}
