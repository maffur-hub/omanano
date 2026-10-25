import QtQuick
import QtQuick.Controls

TextArea {
  id: root

  property color foregroundColor: "#f2f2f2"
  property color accentColor: "#7aa2f7"
  property color mutedColor: root.alpha(foregroundColor, 0.52)

  function alpha(colorValue, opacity) {
    return Qt.rgba(colorValue.r, colorValue.g, colorValue.b, opacity)
  }

  function hexColor(colorValue) {
    function channel(value) {
      var output = Math.round(value * 255).toString(16)
      return output.length < 2 ? "0" + output : output
    }
    return "#" + channel(colorValue.r) + channel(colorValue.g) + channel(colorValue.b)
  }

  // hexColor() drops the alpha channel, so translucent colors (like
  // mutedColor) need this CSS form instead to actually render dimmed.
  function rgbaColor(colorValue) {
    var a = Math.round(colorValue.a * 100) / 100
    return "rgba(" + Math.round(colorValue.r * 255) + ","
      + Math.round(colorValue.g * 255) + ","
      + Math.round(colorValue.b * 255) + "," + a + ")"
  }

  // Headings only carried a font-weight before, so they rendered at body size
  // and never read as titles. Qt rich text sizes inline text with px/pt (no
  // em/% ), so scale the base editor size into an explicit pixel size here.
  function headingPixelSize(level) {
    var base = root.font.pixelSize > 0 ? root.font.pixelSize : 16
    var scale = level <= 1 ? 1.6
      : level === 2 ? 1.4
      : level === 3 ? 1.25 : 1.1
    return Math.round(base * scale)
  }

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
  }

  function preserveIndent(value) {
    var match = String(value || "").match(/^[\t ]+/)
    if (!match) return value
    var indent = match[0].replace(/\t/g, "    ").replace(/ /g, "&nbsp;")
    return indent + value.slice(match[0].length)
  }

  function inlineHighlight(value) {
    var source = String(value || "")
    var output = ""
    var cursor = 0
    var accent = hexColor(accentColor)
    var muted = rgbaColor(mutedColor)
    var fg = hexColor(foregroundColor)
    // One scan, longest/most-specific tokens first so `***x***` beats `**x**`
    // beats `*x*`. Underscore emphasis and bare URLs come last so they never
    // steal a chunk of an earlier token. The content class `[^*\n]*[^*\s\n]`
    // forbids leading/trailing whitespace (CommonMark skips `* foo*` / `*foo *`),
    // and because QML's regex engine has no lookbehind, intraword underscores
    // (`foo_bar_baz`) are rejected with the `index - 1` check below instead.
    var tokenPattern = /`[^`\n]+`|\[[^\]\n]+\]\([^\s()\n]+\)|\*\*\*(?!\s)[^*\n]*[^*\s\n]\*\*\*|___(?!\s)[^_\n]*[^_\s\n]___|\*\*(?!\s)[^*\n]*[^*\s\n]\*\*|__(?!\s)[^_\n]*[^_\s\n]__|~~(?!\s)[^~\n]*[^~\s\n]~~|\*(?!\s)[^*\n]*[^*\s\n]\*|_(?!\s)[^_\n]*[^_\s\n]_|https?:\/\/[^\s<>()]+/g
    var match
    while ((match = tokenPattern.exec(source)) !== null) {
      var index = match.index
      var token = match[0]
      if (token.charAt(0) === "_" && index > 0 && /[A-Za-z0-9]/.test(source.charAt(index - 1))) {
        output += escapeHtml(source.slice(cursor, index + 1))
        cursor = index + 1
        continue
      }
      output += escapeHtml(source.slice(cursor, index))
      var first = token.charAt(0)
      if (first === "`") {
        output += "<span style=\"color:" + accent + ";\">" + escapeHtml(token) + "</span>"
      } else if (first === "[") {
        var link = token.match(/^\[([^\]\n]+)\]\(([^\s()\n]+)\)$/)
        output += "<span style=\"color:" + muted + ";\">[</span>"
          + "<span style=\"color:" + accent + "; text-decoration:underline;\">" + escapeHtml(link[1]) + "</span>"
          + "<span style=\"color:" + muted + ";\">](</span>"
          + "<span style=\"color:" + muted + ";\">" + escapeHtml(link[2]) + "</span>"
          + "<span style=\"color:" + muted + ";\">)</span>"
      } else if (first === "~") {
        output += "<span style=\"color:" + muted + ";\">~~</span>"
          + "<span style=\"color:" + fg + ";\"><s>" + escapeHtml(token.slice(2, -2)) + "</s></span>"
          + "<span style=\"color:" + muted + ";\">~~</span>"
      } else if (first === "*" || first === "_") {
        var markerLen = (token.slice(0, 3) === "***" || token.slice(0, 3) === "___") ? 3
          : (token.slice(0, 2) === "**" || token.slice(0, 2) === "__") ? 2 : 1
        var inner = escapeHtml(token.slice(markerLen, -markerLen))
        // Native tags print bold/italic more reliably than inline font-* CSS.
        var emphasis = markerLen === 3 ? "<b><i>" + inner + "</i></b>"
          : markerLen === 2 ? "<b>" + inner + "</b>" : "<i>" + inner + "</i>"
        output += "<span style=\"color:" + muted + ";\">" + escapeHtml(token.slice(0, markerLen)) + "</span>"
          + "<span style=\"color:" + fg + ";\">" + emphasis + "</span>"
          + "<span style=\"color:" + muted + ";\">" + escapeHtml(token.slice(-markerLen)) + "</span>"
      } else {
        var trailing = token.match(/[.,;:!?\]\}]+$/)
        var suffix = trailing ? trailing[0] : ""
        var url = suffix ? token.slice(0, -suffix.length) : token
        output += "<span style=\"color:" + accent + "; text-decoration:underline;\">" + escapeHtml(url) + "</span>" + escapeHtml(suffix)
      }
      cursor = index + token.length
    }
    output += escapeHtml(source.slice(cursor))
    return preserveIndent(output)
  }

  function highlightedMarkdown(value) {
    var lines = String(value || "").split("\n")
    var output = []
    var inCodeBlock = false
    var accent = hexColor(accentColor)
    var muted = hexColor(mutedColor)
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var fence = line.match(/^(\s*)(```|~~~)/)
      if (fence) {
        output.push(preserveIndent(escapeHtml(line.slice(0, fence[1].length)))
          + "<span style=\"color:" + accent + ";\">" + escapeHtml(line.slice(fence[1].length)) + "</span>")
        inCodeBlock = !inCodeBlock
        continue
      }
      if (inCodeBlock) {
        output.push("<span style=\"color:" + muted + ";\">" + preserveIndent(escapeHtml(line)) + "</span>")
        continue
      }

      var heading = line.match(/^(\s{0,3})(#{1,6})(\s+)(.*)$/)
      if (heading) {
        output.push(preserveIndent(escapeHtml(heading[1]))
          + "<span style=\"color:" + accent + ";\">" + escapeHtml(heading[2]) + "</span>"
          + escapeHtml(heading[3])
          + "<span style=\"color:" + hexColor(foregroundColor)
            + "; font-size:" + headingPixelSize(heading[2].length) + "px; font-weight:600;\">"
            + inlineHighlight(heading[4]) + "</span>")
        continue
      }

      var task = line.match(/^(\s*[-*+]\s+)(\[[ xX]\])(\s*)/)
      if (task) {
        var taskLength = task[1].length + task[2].length + task[3].length
        output.push(preserveIndent(escapeHtml(task[1]))
          + "<span style=\"color:" + accent + "; font-weight:600;\">" + escapeHtml(task[2]) + "</span>"
          + escapeHtml(task[3]) + inlineHighlight(line.slice(taskLength)))
        continue
      }

      var marker = line.match(/^(\s*)([-*+]|\d+\.|>)(\s+)/)
      if (marker) {
        var markerLength = marker[1].length + marker[2].length + marker[3].length
        output.push(preserveIndent(escapeHtml(marker[1]))
          + "<span style=\"color:" + accent + ";\">" + escapeHtml(marker[2]) + "</span>"
          + escapeHtml(marker[3]) + inlineHighlight(line.slice(markerLength)))
        continue
      }

      output.push(inlineHighlight(line))
    }
    return output.join("<br/>")
  }

  function urlAtPosition(position) {
    var source = String(text || "")
    // Markdown links first: the whole `[text](url)` span (brackets included)
    // is clickable and must win over the bare URL that sits inside the parens.
    var linkPattern = /\[[^\]\n]+\]\([^\s()\n]+\)/g
    var match
    while ((match = linkPattern.exec(source)) !== null) {
      if (position >= match.index && position < match.index + match[0].length) {
        var link = match[0].match(/^\[[^\]\n]+\]\(([^\s()\n]+)\)$/)
        if (link) return link[1]
      }
    }
    var pattern = /https?:\/\/[^\s<>()]+/g
    while ((match = pattern.exec(source)) !== null) {
      var url = match[0].replace(/[.,;:!?\]\}]+$/, "")
      if (position >= match.index && position <= match.index + url.length) return url
    }
    return ""
  }

  // IME preedit text is not part of `text` until conversion is committed, so
  // the syntax layer cannot render it. Temporarily reveal the native editor
  // while composing; the highlighted layer returns immediately on commit.
  color: inputMethodComposing ? foregroundColor : "transparent"
  selectedTextColor: foregroundColor
  selectionColor: alpha(accentColor, 0.5)

  cursorDelegate: Rectangle {
    width: 1
    color: root.accentColor
  }

  // The highlighted layer is a separate Text over this (transparent) editor, so
  // its lines must advance at exactly the editor's line spacing. Larger heading
  // glyphs would otherwise grow their own line box and push every following
  // line down, desyncing the caret/selection from the visible text.
  FontMetrics {
    id: editorMetrics
    font: root.font
  }

  background: Item {
    opacity: root.inputMethodComposing ? 0 : 1

    Text {
      x: root.leftPadding
      y: root.topPadding
      width: Math.max(0, root.width - root.leftPadding - root.rightPadding)
      text: root.highlightedMarkdown(root.text)
      textFormat: Text.RichText
      wrapMode: Text.Wrap
      lineHeightMode: Text.FixedHeight
      lineHeight: Math.ceil(editorMetrics.height)
      color: root.foregroundColor
      font.family: root.font.family
      font.pixelSize: root.font.pixelSize
    }
  }

  TapHandler {
    acceptedButtons: Qt.LeftButton
    acceptedModifiers: Qt.ControlModifier
    onTapped: function(eventPoint) {
      var position = root.positionAt(eventPoint.position.x, eventPoint.position.y)
      var url = root.urlAtPosition(position)
      if (url) Qt.openUrlExternally(url)
    }
  }
}
