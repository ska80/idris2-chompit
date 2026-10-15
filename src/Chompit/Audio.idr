module Chompit.Audio

import Chompit.Types
import Chompit.Game

import SDL3
import SDL3.Mixer
import SDL3.Mixer.Scoped

%default covering

export
record SoundBank where
  constructor MkSoundBank
  mixer : Mixer DeviceOutput
  tracks : List (String, Track)
  looping : PlayOptions

withTracks : Mixer DeviceOutput -> String -> List String ->
             (List (String, Track) -> IO (Either String a)) -> IO (Either String a)
withTracks mixer directory [] action = action []
withTracks mixer directory (name :: names) action = withTrack mixer $ \track => do
  Right () <- withAudio mixer (directory ++ "/" ++ name ++ ".wav") Predecode (\asset => do
    True <- setTrackAudio track (Just asset) | False => Left <$> getError
    pure (Right ())) | Left err => pure (Left err)
  withTracks mixer directory names $ \rest => action ((name, track) :: rest)

export
withSounds : String -> (SoundBank -> IO (Either String a)) -> IO (Either String a)
withSounds directory action = withMixerLibrary $ withMixer $ \mixer =>
  withTracks mixer directory ["title", "begin", "chomp-low", "chomp-high", "power", "eat-ghost",
    "death", "clear", "fruit", "extra-life", "siren", "frightened"] $ \tracks =>
      withPlayOptions $ \looping => do
        True <- setMixerGain mixer 0.65 | False => Left <$> getError
        True <- setPlayLoops looping LoopForever | False => Left <$> getError
        action (MkSoundBank mixer tracks looping)

cueName : Cue -> String
cueName ChompLow = "chomp-low"
cueName ChompHigh = "chomp-high"
cueName Energize = "power"
cueName GhostEaten = "eat-ghost"
cueName PlayerDied = "death"
cueName LevelWon = "clear"
cueName BeginGame = "begin"
cueName FruitEaten = "fruit"
cueName BonusLife = "extra-life"

findTrack : String -> List (String, Track) -> Maybe Track
findTrack _ [] = Nothing
findTrack name ((key, track) :: rest) = if name == key then Just track else findTrack name rest

play : SoundBank -> String -> Bool -> IO Bool
play bank name loop = case findTrack name bank.tracks of
  Nothing => pure False
  Just track => playTrack track (if loop then Just bank.looping else Nothing)

ambient : Game -> String
ambient game = case game.phase of
  Title => "title"
  Playing => if game.frightened > 0 then "frightened" else "siren"
  _ => ""

stopAmbient : SoundBank -> String -> IO Bool
stopAmbient bank name = case findTrack name bank.tracks of
  Nothing => pure True
  Just track => stopTrack track 0

pauseAll : Bool -> List (String, Track) -> IO Bool
pauseAll paused [] = pure True
pauseAll paused ((_, track) :: rest) = do
  True <- (if paused then pauseTrack track else resumeTrack track) | False => pure False
  pauseAll paused rest

playCues : SoundBank -> List Cue -> IO Bool
playCues bank [] = pure True
playCues bank (cue :: rest) = do
  True <- play bank (cueName cue) False | False => pure False
  playCues bank rest

export
startAudio : Maybe SoundBank -> Game -> IO (Either String ())
startAudio Nothing _ = pure (Right ())
startAudio (Just bank) game = do
  True <- play bank "title" True | False => Left <$> getError
  pure (Right ())

export
updateAudio : Maybe SoundBank -> Game -> Game -> Bool -> IO (Either String ())
updateAudio Nothing _ _ _ = pure (Right ())
updateAudio (Just bank) old new muted = do
  True <- setMixerGain bank.mixer (if muted then 0 else 0.65) | False => Left <$> getError
  True <- (if ambient old /= ambient new then do
    True <- stopAmbient bank (ambient old) | False => pure False
    if ambient new == "" then pure True else play bank (ambient new) True
    else pure True) | False => Left <$> getError
  True <- playCues bank new.sounds | False => Left <$> getError
  True <- (if old.paused /= new.paused then pauseAll new.paused bank.tracks else pure True)
    | False => Left <$> getError
  pure (Right ())
