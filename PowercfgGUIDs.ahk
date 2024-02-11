#Requires AutoHotkey v2.0

class PowercfgGUIDs {
    __New() {
        buttonslines := getpcqlines("scheme_current sub_buttons", 4)
        scheme_current := getguid(buttonslines[1])
        sub_buttons := getguid(buttonslines[3])
        ; https://learn.microsoft.com/windows-hardware/customize/power-settings/power-button-and-lid-settings-lid-switch-close-action
        lidaction := "5ca83367-6e45-459f-a27b-476b1d01c936" ; not available from powercfg

        this.lid := {
            guid1: scheme_current
            , guid2: sub_buttons
            , guid3: lidaction
            , max: 3
        }

        videolines := getpcqlines("scheme_current sub_video videoidle", 12)
        sub_video := getguid(videolines[3])
        videoidle := getguid(videolines[5])

        this.video := {
            guid1: scheme_current
            , guid2: sub_video
            , guid3: videoidle
            , max: 0xffffffff
        }

        sleeplines := getpcqlines("scheme_current sub_sleep standbyidle", 12)
        sub_sleep := getguid(sleeplines[3])
        standbyidle := getguid(sleeplines[5])

        this.stand := {
            guid1: scheme_current
            , guid2: sub_sleep
            , guid3: standbyidle
            , max: 0xffffffff
        }

        hibernatelines := getpcqlines("scheme_current sub_sleep hibernateidle", 12)
        hibernateidle := getguid(hibernatelines[5])
        this.hiber := {
            guid1: scheme_current
            , guid2: sub_sleep
            , guid3: hibernateidle
            , max: 0xffffffff
        }

        return

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
}
