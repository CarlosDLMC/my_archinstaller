
hl.config({ animations = { enabled = true } })

-- No bounce: every curve stays inside y = [0, 1]. A y above 1 overshoots the
-- target and springs back; a y below 0 pulls back before it starts moving.
hl.curve("wind", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.0} } })
hl.curve("liner", { type = "bezier", points = { {1, 1}, {1, 1} } })
-- Window animations follow omarchy (omacom/omarchy, default/hypr/looknfeel.lua):
-- windows pop in/out at 87% size, moves/resizes ease out. wind spends ~90% of its
-- time on the last ~10% of the distance, so a resized window's border crept to
-- its edge after the content was already there.
hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.curve("linear", { type = "bezier", points = { {0, 0}, {1, 1} } })
hl.curve("almostLinear", { type = "bezier", points = { {0.5, 0.5}, {0.75, 1.0} } })
hl.curve("quick", { type = "bezier", points = { {0.15, 0}, {0.1, 1} } })

hl.animation({ leaf = "windows", enabled = true, speed = 3.79, bezier = "easeOutQuint"})
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%"})
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%"})
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.79, bezier = "easeOutQuint"})
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint"})
-- "once", not "loop": the border here is one colour (UserDecorations.lua), so a
-- looping angle rotated nothing, yet redrew every window's border every frame -
-- the compositor never idled (GPU awake, no panel self-refresh). Set it back to
-- "loop" with a gradient border, e.g. RainbowBorders.
hl.animation({ leaf = "borderangle", enabled = true, speed = 100, bezier = "liner", style = "once"}) -- was 180: clamped, Lua caps speed at 100
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick"})
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear"})
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear"})
-- No fade when focus moves between windows.
hl.animation({ leaf = "fadeSwitch", enabled = false })
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "wind"})

-- animations for -git or version >0.42.0
-- In and Out share one curve and speed, so the old and new workspace slide
-- together as one strip instead of drifting apart mid-switch.
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 5, bezier = "wind", style = "slide"})
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 5, bezier = "wind", style = "slide"})
