// app/javascript/controllers/dialog_controller.js
//
// The app's data-controller="dialog": @stimulus-components/dialog, except
// that on a touch screen opening a dialog doesn't drop the cursor into its
// first text field. showModal() focuses the first thing it can (iOS skips
// buttons, so that's usually a text box), and a form that loads into the
// dialog afterwards may autofocus one too — either pops the keyboard up and
// shifts the page around. There the dialog itself takes focus instead, and
// the keyboard waits until a field is tapped. With a mouse, the first field
// still gets the cursor.

import Dialog from "@stimulus-components/dialog"

const TOUCH = window.matchMedia("(pointer: coarse)")
const TEXT_FIELD = "input:not([type=checkbox], [type=radio], [type=range], [type=color], [type=file], [type=submit], [type=button], [type=reset], [type=image]), textarea, select, [contenteditable]"

export default class extends Dialog {
    connect() {
        super.connect()
        this.keepKeyboardDown = this.keepKeyboardDown.bind(this)
        this.element.addEventListener("turbo:frame-render", this.keepKeyboardDown)
    }

    disconnect() {
        super.disconnect()
        this.element.removeEventListener("turbo:frame-render", this.keepKeyboardDown)
    }

    open() {
        super.open()
        this.keepKeyboardDown()
    }

    keepKeyboardDown() {
        const dialog = this.dialogTarget
        const focused = document.activeElement
        if (!TOUCH.matches || !dialog.open || !dialog.contains(focused) || !focused.matches(TEXT_FIELD)) return

        dialog.tabIndex = -1
        dialog.focus({ preventScroll: true })
    }
}
