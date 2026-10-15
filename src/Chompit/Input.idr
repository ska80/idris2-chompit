module Chompit.Input

import Chompit.Types

import SDL3

%default total

export
keyCommand : Scancode -> Keycode -> Command
keyCommand scan (MkKeycode raw) =
  let key = MkKeycode (if raw >= 65 && raw <= 90 then raw + 32 else raw) in
  if key == escapeKey || key == MkKeycode 113 then Quit
  else if key == MkKeycode 13 || key == MkKeycode 32 then Start
  else if key == MkKeycode 112 then Pause
  else if key == MkKeycode 109 then ToggleMute
  else if scan == MkScancode 82 || key == MkKeycode 119 then Turn North
  else if scan == MkScancode 80 || key == MkKeycode 97 then Turn West
  else if scan == MkScancode 81 || key == MkKeycode 115 then Turn South
  else if scan == MkScancode 79 || key == MkKeycode 100 then Turn East
  else Ignore

export
commandFor : WindowID -> Event -> Either String Command
commandFor identifier event = case event of
  QuitEvent _ => Right Quit
  WindowCloseEvent _ target => Right (if target == identifier then Quit else Ignore)
  WindowFocusLostEvent _ target => Right (if target == identifier then LoseFocus else Ignore)
  KeyboardEvent _ (MkKeyboardData target Pressed scan key _ repeated) =>
    Right (if target /= identifier || repeated then Ignore else keyCommand scan key)
  RenderDeviceResetEvent _ target => if target == identifier
    then Left "The renderer device reset. Restart Chompit." else Right Ignore
  _ => Right Ignore
