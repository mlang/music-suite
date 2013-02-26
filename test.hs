
module Main where

import Data.Default
import Data.Semigroup
import Data.Default
import System.Posix.Process

import Music.MusicXml
import Music.MusicXml.Pitch
import qualified Music.MusicXml.Dynamics as Dynamics

-- division 38880 (2^5*3^5*5)

instance Default NoteProps where
    def = NoteProps Nothing (Just (1/4, Nothing)) 0 Nothing

setVal :: NoteVal -> NoteProps -> NoteProps
setVal v x = x { noteType = Just (v, Nothing) }


score = Partwise
    (ScoreAttrs [])
    (ScoreHeader 
        Nothing
        (Just "Frère Jaques") 
        (Just (Identification [Creator "composer" "Anonymous"])) 
        [
            Part "P1" "Vln" Nothing,
            Part "P2" "Vla" Nothing,
            Part "P3" "Vc"  Nothing
        ])
    [
        (PartAttrs "P1", [
        
            (MeasureAttrs 1, [                
                -- setting attributes as this is first measure 
                MusicAttributes (Divisions 256)
                ,
                MusicAttributes (Clef GClef 2)
                ,
                MusicAttributes (Key (-3) Major)
                ,
                MusicAttributes (Time CommonTime)
                ,
                            
                MusicNote (Note (Pitched noChord (C, noSemitones, 4)) 256 noTies def)
                , 
                MusicNote (Note (Pitched noChord (D, noSemitones, 4)) 256 noTies def)
                , 
                MusicNote (Note (Pitched noChord (E, Just (-1),   4)) 128 noTies (setVal (1/8) def))
                , 
                MusicNote (Note (Pitched noChord (D, noSemitones, 4)) 128 noTies (setVal (1/8) def))
                , 
                MusicNote (Note (Pitched noChord (C, noSemitones, 4)) 256 noTies def)  
            ])
            ,
            (MeasureAttrs 2, [                      
                MusicNote (Note (Pitched noChord (C, noSemitones, 4)) 256 noTies def)
                , 
                MusicNote (Note (Pitched noChord (D, noSemitones, 4)) 256 noTies def)
                , 
                MusicNote (Note (Pitched noChord (E, Just (-1),   4)) 128 noTies (setVal (1/8) def))
                , 
                MusicNote (Note (Pitched noChord (D, noSemitones, 4)) 128 noTies (setVal (1/8) def))
                , 
                MusicNote (Note (Pitched noChord (C, noSemitones, 4)) 256 noTies def)   
            ])
        ])
        ,
        
        (PartAttrs "P2", [
            (MeasureAttrs 1, [                
                MusicAttributes (Divisions 256)
                ,
                MusicAttributes (Key (-3) Major)
                ,
                MusicAttributes (Clef CClef 3)
                ,
                MusicNote (Note (Pitched noChord (C, noSemitones, 4)) 256 noTies def)
                ,
                MusicNote (Note (Pitched noChord (G, noSemitones, 3)) 256 noTies def)
                ,
                MusicNote (Note (Pitched noChord (C, noSemitones, 4)) 512 noTies (setVal (1/2) def))
            ])
            ,
            (MeasureAttrs 2, [                
                MusicNote (Note (Pitched noChord (C, noSemitones, 4)) 256 noTies def)
                ,
                MusicNote (Note (Pitched noChord (G, noSemitones, 3)) 256 noTies def)
                ,
                MusicNote (Note (Pitched noChord (C, noSemitones, 4)) 512 noTies (setVal (1/2) def))                
            ])
            ,
            (MeasureAttrs 3, [
                MusicNote (Note (Rest noChord (C, 4)) 1024 noTies (setVal (1/1) def))
            ])
        ])
        ,    

        (PartAttrs "P3", [
            (MeasureAttrs 1, [                
                MusicAttributes (Divisions 256)
                ,
                MusicAttributes (Key (-3) Major)
                ,
                MusicAttributes (Clef FClef 4)
                ,
                MusicNote (Note (Pitched noChord (C, noSemitones, 3)) 1024 noTies (setVal (1/1) def))
            ])
            ,
            (MeasureAttrs 2, [                
                MusicNote (Note (Pitched noChord (C, noSemitones, 3)) 1024 noTies (setVal (1/1) def))
            ])
            ,
            (MeasureAttrs 3, [                
                MusicNote (Note (Rest noChord (D, 3)) 1024 noTies (setVal (1/1) def))
            ])
        ])
    ]





main = openScore

showScore = putStrLn $ showXml $ score
openScore = openSib score

openSib :: Score -> IO ()
openSib score = 
    do  writeFile "test.xml" (showXml score)
        execute "open" ["-a", "/Applications/Sibelius 6.app/Contents/MacOS/Sibelius 6", "test.xml"]

openLy :: Score -> IO ()
openLy score = 
    do  writeFile "test.xml" (showXml score)
        execute "musicxml2ly" ["test.xml"]
        execute "lilypond" ["test.ly"]
        execute "open" ["test.pdf"]

execute :: FilePath -> [String] -> IO ()
execute program args = do
    forkProcess $ executeFile program True args Nothing
    return ()
