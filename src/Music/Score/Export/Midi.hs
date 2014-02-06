
{-# LANGUAGE
    TypeFamilies,
    DeriveFunctor,
    DeriveFoldable,
    DeriveDataTypeable,
    GeneralizedNewtypeDeriving,
    FlexibleInstances,
    FlexibleContexts,
    ConstraintKinds,
    ScopedTypeVariables,
    TypeOperators,
    OverloadedStrings,
    NoMonomorphismRestriction #-}

-------------------------------------------------------------------------------------
-- |
-- Copyright   : (c) Hans Hoglund 2012
--
-- License     : BSD-style
--
-- Maintainer  : hans@hanshoglund.se
-- Stability   : experimental
-- Portability : non-portable (TF,GNTD)
--
-------------------------------------------------------------------------------------

module Music.Score.Export.Midi (
        HasMidi(..),
        HasMidiPart,
        HasMidiProgram(..),
        toMidi,
        toMidiTrack,
        writeMidi,
        playMidi,
        playMidiIO,
  ) where

import Prelude hiding (foldr, concat, foldl, mapM, concatMap, maximum, sum, minimum)

import Data.Semigroup
import Data.Ratio
import Data.String
import Control.Lens hiding ((|>))
import Control.Applicative
import Control.Monad hiding (mapM)
import Control.Monad.Plus
import Control.Arrow
import Data.Maybe
import Data.Either
import Data.Foldable
import Data.Typeable
import Data.Traversable
import Data.Function (on)
import Data.Ord (comparing)
import Data.VectorSpace
import Data.AffineSpace
import Data.AffineSpace.Point
import Data.Basis

import Control.Reactive hiding (Event)
import Control.Reactive.Midi
import qualified Control.Reactive as R

import Music.Time
import Music.Pitch.Literal
import Music.Dynamics.Literal
import Music.Score.Rhythm
import Music.Score.Track
import Music.Score.Voice
import Music.Score.Score
import Music.Score.Combinators
import Music.Score.Chord
import Music.Score.Pitch
import Music.Score.Ties
import Music.Score.Part
import Music.Score.Articulation
import Music.Score.Dynamics
import Music.Score.Ornaments
import Music.Score.Export.Common

import qualified Codec.Midi as Midi
import qualified Music.MusicXml.Simple as Xml
import qualified Music.Lilypond as Lilypond
import qualified Text.Pretty as Pretty
import qualified Data.Map as Map
import qualified Data.List as List


-- | Class of types with MIDI-compatible parts.
type HasMidiPart a = (HasPart' a, HasMidiProgram (Part a))

-- | Class of part types with an associated MIDI program number.
class HasMidiProgram a where
    getMidiChannel :: a -> Midi.Channel
    getMidiProgram :: a -> Midi.Preset
    getMidiChannel _ = 0

instance HasMidiProgram () where
    getMidiProgram _ = 0
instance HasMidiProgram Double where
    getMidiProgram = fromIntegral . floor
instance HasMidiProgram Float where
    getMidiProgram = fromIntegral . floor
instance HasMidiProgram Int where
    getMidiProgram = id
instance HasMidiProgram Integer where
    getMidiProgram = fromIntegral
instance (Integral a, HasMidiProgram a) => HasMidiProgram (Ratio a) where
    getMidiProgram = fromIntegral . floor
    
-- |
-- Class of types that can be converted to MIDI.
--
-- Numeric types are interpreted as notes with a default velocity, pairs are
-- interpreted as @(pitch, velocity)@ pairs.
--
-- Minimal definition: 'getMidi'. Given 'getMidiScore', 'getMidi' can be implemented
-- as @getMidiScore . return@.
--
class HasMidi a where

    -- | Convert a value to a MIDI score.
    --   Typically, generates an /on/ event using 'note' followed by an optional /off/ event.
    getMidi :: a -> Score Midi.Message

    -- | Convert a score to a MIDI score.
    --   The default definition can be overriden for efficiency.
    getMidiScore :: Score a -> Score Midi.Message
    getMidiScore = (>>= getMidi)


instance HasMidi (Integer, Integer) where
    getMidi (p,v) = mempty
        |> return (Midi.NoteOn 0 (fromIntegral p) (fromIntegral v))
        |> return (Midi.NoteOff 0 (fromIntegral p) (fromIntegral v))

instance HasMidi Midi.Message               where   getMidi = return
instance HasMidi Int                        where   getMidi = getMidi . toInteger
instance HasMidi Float                      where   getMidi = getMidi . toInteger . round
instance HasMidi Double                     where   getMidi = getMidi . toInteger . round
instance Integral a => HasMidi (Ratio a)    where   getMidi = getMidi . toInteger . round
instance HasMidi a => HasMidi (Maybe a)     where   getMidi = getMidiScore . mfromMaybe
instance HasMidi Integer                    where   getMidi x = getMidi (x,100::Integer)

instance HasMidi a => HasMidi (PartT n a) where
    getMidi (PartT (_,a))                           = getMidi a
instance HasMidi a => HasMidi (ChordT a) where
    getMidi = pcat . fmap getMidi . getChordT
instance HasMidi a => HasMidi (TieT a) where
    getMidi (TieT (_,a,_))                          = getMidi a
instance HasMidi a => HasMidi (DynamicT a) where
    getMidi (DynamicT (ec,ed,l,a,bc,bd))            = getMidi a
instance HasMidi a => HasMidi (ArticulationT a) where
    getMidi (ArticulationT (es,us,al,sl,a,bs))      = getMidi a
instance HasMidi a => HasMidi (TremoloT a) where
    getMidi (TremoloT (_,a))                        = getMidi a
instance HasMidi a => HasMidi (TextT a) where
    getMidi (TextT (_,a))                           = getMidi a
instance HasMidi a => HasMidi (HarmonicT a) where
    getMidi (HarmonicT (_,a))                       = getMidi a
instance HasMidi a => HasMidi (SlideT a) where
    getMidi (SlideT (_,_,a,_,_))                    = getMidi a


-- |
-- Convert a score to a MIDI file representation.
--
toMidi :: forall a . (HasMidiPart a, HasMidi a) => Score a -> Midi.Midi
toMidi score = Midi.Midi fileType divisions' (controlTrack : eventTracks)
    where
        -- Each track needs TrackEnd
        -- We place it long after last event just in case (necessary?) 
        endDelta        = 10000
        fileType        = Midi.MultiTrack
        divisions       = 1024
        divisions'      = Midi.TicksPerBeat divisions
        controlTrack    = [(0, Midi.TempoChange 1000000), (endDelta, Midi.TrackEnd)]
        eventTracks     = fmap ((<> [(endDelta, Midi.TrackEnd)]) . uncurry setProgramChannel . second scoreToMTrack) 
                                $ extractParts' score

        setProgramChannel :: Part a -> Midi.Track Midi.Ticks -> Midi.Track Midi.Ticks
        setProgramChannel p = ([(0, Midi.ProgramChange ch prg)] <>) . fmap (fmap (setChannel ch))
            where
                ch = getMidiChannel p
                prg = getMidiProgram p

        scoreToMTrack :: Score a -> Midi.Track Midi.Ticks
        scoreToMTrack = fmap (\(t,_,x) -> (round ((t.-. origin) ^* divisions), x)) . toRelative . (^. events) . getMidiScore

        -- TODO render voices separately

-- |
-- Convert a score to a track of MIDI messages.
--
toMidiTrack :: HasMidi a => Score a -> Track Message
toMidiTrack = track . fmap (\(t,_,m) -> (t, m)) . (^. events) . getMidiScore

-- |
-- Convert a score MIDI and write to a file.
--
writeMidi :: (HasMidiPart a, HasMidi a) => FilePath -> Score a -> IO ()
writeMidi path sc = Midi.exportFile path (toMidi sc)

-- |
-- Convert a score to a MIDI event.
--
playMidi :: HasMidi a => String -> Score a -> R.Event MidiMessage
playMidi dest x = midiOut midiDest $ playback trig (pure $ toTrack $ startAt 0.2 x)
    where
        -- trig        = accumR 0 ((+ 0.005) <$ pulse 0.005)
        trig        = time
        toTrack     = fmap (\(t,_,m) -> (t .-. origin, m)) . (^. events) . getMidiScore
        midiDest    = fromJust $ unsafeGetReactive (findDestination  $ pure dest)

-- |
-- Convert a score to a MIDI event and run it.
--
playMidiIO :: HasMidi a => String -> Score a -> IO ()
playMidiIO dest = runLoop . playMidi dest



setChannel :: Midi.Channel -> Midi.Message -> Midi.Message
setChannel c = go
    where
        go (NoteOff _ k v)       = NoteOff c k v
        go (NoteOn _ k v)        = NoteOn c k v
        go (KeyPressure _ k v)   = KeyPressure c k v
        go (ControlChange _ n v) = ControlChange c n v
        go (ProgramChange _ p)   = ProgramChange c p
        go (ChannelPressure _ p) = ChannelPressure c p
        go (PitchWheel _ w)      = PitchWheel c w
        go (ChannelPrefix _)     = ChannelPrefix c
        

