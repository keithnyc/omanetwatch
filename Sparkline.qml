import QtQuick

Canvas {
  id: root

  property var history: []
  property color lineColor: "white"
  property color failureColor: "red"
  property color mutedColor: "gray"

  antialiasing: true

  onHistoryChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onFailureColorChanged: requestPaint()
  onMutedColorChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    ctx.clearRect(0, 0, width, height)

    var samples = Array.isArray(history) ? history : []
    var pad = 2
    var chartWidth = Math.max(1, width - pad * 2)
    var chartHeight = Math.max(1, height - pad * 2)

    ctx.globalAlpha = 0.22
    ctx.strokeStyle = mutedColor
    ctx.lineWidth = 1
    ctx.beginPath()
    ctx.moveTo(pad, height - pad)
    ctx.lineTo(width - pad, height - pad)
    ctx.stroke()
    ctx.globalAlpha = 1

    if (samples.length === 0) return

    var maxLatency = 1
    for (var i = 0; i < samples.length; i++) {
      if (samples[i].ok) maxLatency = Math.max(maxLatency, Number(samples[i].latencyMs || 0))
    }

    function xFor(index) {
      return pad + (samples.length === 1 ? chartWidth / 2 : index * chartWidth / (samples.length - 1))
    }

    function yFor(sample) {
      var normalized = Math.max(0, Number(sample.latencyMs || 0)) / maxLatency
      return height - pad - normalized * chartHeight
    }

    ctx.strokeStyle = lineColor
    ctx.lineWidth = 1.6
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.beginPath()
    var drawing = false
    var healthyCount = 0
    for (var j = 0; j < samples.length; j++) {
      if (!samples[j].ok) {
        drawing = false
        continue
      }
      var x = xFor(j)
      var y = yFor(samples[j])
      healthyCount++
      if (!drawing) {
        ctx.moveTo(x, y)
        drawing = true
      } else ctx.lineTo(x, y)
    }
    ctx.stroke()

    if (healthyCount === 1) {
      for (var single = 0; single < samples.length; single++) {
        if (!samples[single].ok) continue
        ctx.fillStyle = lineColor
        ctx.beginPath()
        ctx.arc(xFor(single), yFor(samples[single]), 1.8, 0, Math.PI * 2)
        ctx.fill()
        break
      }
    }

    ctx.fillStyle = failureColor
    for (var failed = 0; failed < samples.length; failed++) {
      if (samples[failed].ok) continue
      ctx.fillRect(xFor(failed) - 1.5, height - pad - 5, 3, 5)
    }
  }
}
