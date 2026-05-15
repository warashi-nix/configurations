vim9script

# --------------------------------------------------
#  OSC 52
# --------------------------------------------------

packadd osc52

def Available(): bool
  return true
enddef

v:clipproviders["osc52"] = {
  available: Available,
  copy: {
    '+': osc52#Copy,
    '*': osc52#Copy,
  },
  paste: {
    '+': osc52#Paste,
    '*': osc52#Paste,
  },
}

set clipmethod=osc52
