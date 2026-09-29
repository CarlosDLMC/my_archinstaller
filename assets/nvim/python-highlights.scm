;extends
; Extra captures for pycharm-dark (colors/pycharm-dark.lua). nvim-treesitter's
; Python query gives call-site keyword arguments the same @variable.parameter as
; real parameters, and __dunder__ names only @constant.builtin or @constructor.
; PyCharm colours both on their own, so they get their own captures here.
; Priority 101 puts them above the stock captures (100) for the same node.

; f(sep="") - PyCharm's PY.KEYWORD_ARGUMENT
(keyword_argument
  name: (identifier) @variable.parameter.keyword
  (#set! priority 101))

; __init__, __name__, obj.__dict__ - PyCharm's PY.PREDEFINED_DEFINITION / USAGE
((identifier) @function.dunder
  (#lua-match? @function.dunder "^__[%w_]*__$")
  (#set! priority 101))
