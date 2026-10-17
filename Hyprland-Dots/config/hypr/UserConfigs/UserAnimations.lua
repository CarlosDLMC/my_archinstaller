
hl.config({ animations = { enabled = true } })

-- No bounce: every curve stays inside y = [0, 1]. A y above 1 overshoots the
-- target and springs back; a y below 0 pulls back before it starts moving.
hl.curve("wind", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.0} } })
hl.curve("winIn", { type = "bezier", points = { {0.1, 0.9}, {0.1, 1.0} } })
hl.curve("winOut", { type = "bezier", points = { {0.3, 0.0}, {0, 1} } })
hl.curve("liner", { type = "bezier", points = { {1, 1}, {1, 1} } })
hl.curve("smoothOut", { type = "bezier", points = { {0.5, 0}, {0.99, 0.99} } })
-- Window moves/resizes and closing follow omarchy's timings (default/hypr/looknfeel.lua).
-- wind spends ~90% of its time on the last ~10% of the distance, so a resized
-- window's border crept to its edge after the content was already there.
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.curve("linear", { type = "bezier", points = { {0, 0}, {1, 1} } })
hl.curve("almostLinear", { type = "bezier", points = { {0.5, 0.5}, {0.75, 1.0} } })

hl.animation({ leaf = "windows", enabled = true, speed = 3.79, bezier = "easeOutQuint", style = "slide"})
hl.animation({ leaf = "windowsIn", enabled = true, speed = 5, bezier = "winIn", style = "slide"})
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "slide"})
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.79, bezier = "easeOutQuint", style = "slide"})
hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "liner"})
-- "once", not "loop": the border here is one colour (UserDecorations.lua), so a
-- looping angle rotated nothing, yet redrew every window's border every frame -
-- the compositor never idled (GPU awake, no panel self-refresh). Set it back to
-- "loop" with a gradient border, e.g. RainbowBorders.
hl.animation({ leaf = "borderangle", enabled = true, speed = 100, bezier = "liner", style = "once"}) -- was 180: clamped, Lua caps speed at 100
hl.animation({ leaf = "fade", enabled = true, speed = 3, bezier = "smoothOut"})
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear"})
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "wind"})

-- animations for -git or version >0.42.0
-- In and Out share one curve and speed, so the old and new workspace slide
-- together as one strip instead of drifting apart mid-switch.
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 5, bezier = "wind", style = "slide"})
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 5, bezier = "wind", style = "slide"})
