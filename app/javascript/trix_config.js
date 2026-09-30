// Trims the Trix editor (recipe step instructions) down to what's useful
// here: bold, italic, strikethrough, links, headings and attachments. Lists,
// quotes, code blocks and indenting are removed — both their toolbar buttons
// and the formats themselves, so pasted lists/quotes/code come in as plain
// paragraphs rather than formatting nobody can edit anymore.
//
// Runs as soon as it's imported, right after "trix": Trix registers its
// <trix-toolbar>/<trix-editor> elements on a setTimeout, so this is always
// in place before the first editor builds its toolbar.

const Trix = window.Trix

const REMOVED_BLOCK_FORMATS = ["quote", "code", "bullet", "bulletList", "number", "numberList"]

const REMOVED_BUTTONS = [
  '[data-trix-attribute="quote"]',
  '[data-trix-attribute="code"]',
  '[data-trix-attribute="bullet"]',
  '[data-trix-attribute="number"]',
  '[data-trix-action="decreaseNestingLevel"]',
  '[data-trix-action="increaseNestingLevel"]'
].join(", ")

REMOVED_BLOCK_FORMATS.forEach((name) => { delete Trix.config.blockAttributes[name] })

// With those formats gone, Trix would read a list's items as one run-on
// line ("Chop onionsBrown the beef"). So lists, quotes and code blocks are
// turned into plain lines first — each list item its own line — both for
// content already saved with them (before the editor loads it) and for
// anything pasted in.
function flattenRemovedFormats(html) {
  const template = document.createElement("template")
  template.innerHTML = html
  const root = template.content

  root.querySelectorAll("pre").forEach((pre) => {
    const div = document.createElement("div")
    div.textContent = pre.textContent
    div.innerHTML = div.innerHTML.replace(/\n/g, "<br>")
    pre.replaceWith(div)
  })
  root.querySelectorAll("li, blockquote").forEach((element) => {
    const div = document.createElement("div")
    div.append(...element.childNodes)
    element.replaceWith(div)
  })
  root.querySelectorAll("ul, ol").forEach((list) => list.replaceWith(...list.childNodes))

  return template.innerHTML
}

document.addEventListener("trix-before-initialize", (event) => {
  const input = event.target.inputElement
  if (input?.value) input.value = flattenRemovedFormats(input.value)
})

document.addEventListener("trix-before-paste", (event) => {
  const paste = event.paste
  if (paste?.html) paste.html = flattenRemovedFormats(paste.html)
})

// Start from Trix's own toolbar markup (keeping its labels and translations)
// and just take the unwanted buttons out.
const defaultToolbarHTML = Trix.config.toolbar.getDefaultHTML.bind(Trix.config.toolbar)
Trix.config.toolbar.getDefaultHTML = () => {
  const template = document.createElement("template")
  template.innerHTML = defaultToolbarHTML()
  template.content.querySelectorAll(REMOVED_BUTTONS).forEach((button) => button.remove())
  return template.innerHTML
}
