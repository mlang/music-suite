{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# OPTIONS_GHC
  -fno-warn-name-shadowing
  -fno-warn-unused-imports
  -fno-warn-redundant-constraints #-}

-------------------------------------------------------------------------------------

-------------------------------------------------------------------------------------

-- |
-- Copyright   : (c) Hans Hoglund 2012-2014
--
-- License     : BSD-style
--
-- Maintainer  : hans@hanshoglund.se
-- Stability   : experimental
-- Portability : non-portable (TF,GNTD)
module Music.Score.Export.DynamicNotation
  ( CrescDim (..),
    DynamicNotation (..),
    crescDim,
    dynamicLevel,
    notateDynamic,

    -- * Utility
    removeCloseDynMarks,
  )
where

import Control.Lens -- ()
import Data.AffineSpace
import Data.Functor.Context
import Data.Semigroup
import Music.Score.Dynamics
import Music.Score.Phrases
import Music.Score.Ties
import Music.Time

data CrescDim = NoCrescDim | BeginCresc | EndCresc | BeginDim | EndDim
  deriving (Eq, Ord, Show)

instance Monoid CrescDim where
  mempty = NoCrescDim

instance Semigroup CrescDim where
  NoCrescDim <> a = a
  a <> _ = a

newtype DynamicNotation
  = DynamicNotation {getDynamicNotation :: ([CrescDim], Maybe Double)}
  deriving (Eq, Ord, Show)

instance Wrapped DynamicNotation where

  type Unwrapped DynamicNotation = ([CrescDim], Maybe Double)

  _Wrapped' = iso getDynamicNotation DynamicNotation

instance Rewrapped DynamicNotation DynamicNotation

type instance GetDynamic DynamicNotation = DynamicNotation

instance Transformable DynamicNotation where
  transform _ = id

instance Tiable DynamicNotation where
  toTied (DynamicNotation (beginEnd, marks)) =
    ( DynamicNotation (beginEnd, marks),
      DynamicNotation (mempty, Nothing)
    )

instance Monoid DynamicNotation where

  mempty = DynamicNotation ([], Nothing)

  mappend = (<>)

instance Semigroup DynamicNotation where
  DynamicNotation ([], Nothing) <> y = y
  x <> _ = x

crescDim :: Lens' DynamicNotation [CrescDim]
crescDim = _Wrapped' . _1

dynamicLevel :: Lens' DynamicNotation (Maybe Double)
dynamicLevel = _Wrapped' . _2

-- Given a dynamic value and its context, decide:
--
--   1) Whether we should begin or end a crescendo or diminuendo
--   2) Whether we should display the current dynamic value
--
notateDynamic :: (Ord a, Real a) => Ctxt a -> DynamicNotation
notateDynamic x = DynamicNotation $ over _2 (\t -> if t then Just (realToFrac $ extractCtxt x) else Nothing) $ case getCtxt x of
  (Nothing, _, Nothing) -> ([], True)
  (Nothing, y, Just z) -> case y `compare` z of
    LT -> ([BeginCresc], True)
    EQ -> ([], True)
    GT -> ([BeginDim], True)
  (Just x, y, Just z) -> case (x `compare` y, y `compare` z) of
    (LT, LT) -> ([NoCrescDim], False)
    (LT, EQ) -> ([EndCresc], True)
    (EQ, LT) -> ([BeginCresc], False {-True-})
    (GT, GT) -> ([NoCrescDim], False)
    (GT, EQ) -> ([EndDim], True)
    (EQ, GT) -> ([BeginDim], False {-True-})
    (EQ, EQ) -> ([], False)
    (LT, GT) -> ([EndCresc, BeginDim], True)
    (GT, LT) -> ([EndDim, BeginCresc], True)
  (Just x, y, Nothing) -> case x `compare` y of
    LT -> ([EndCresc], True)
    EQ -> ([], False)
    GT -> ([EndDim], True)

removeCloseDynMarks :: forall s a. (HasPhrases' s a, HasDynamics' a, GetDynamic a ~ DynamicNotation, a ~ SetDynamic (GetDynamic a) a) => s -> s
removeCloseDynMarks = mapPhrasesWithPrevAndCurrentOnset f
  where
    f :: Maybe (Time, Phrase a) -> Time -> Phrase a -> Phrase a
    f Nothing _ x = x
    f (Just (t1, x1)) t2 x =
      if (t2 .-. t1) > 1.5
        || ((x1 ^? (_last . dynamics')) /= (x ^? (_head . dynamics')))
        then x
        else over (_head . mapped) removeDynMark x

removeDynMark :: (HasDynamics' a, GetDynamic a ~ DynamicNotation, a ~ SetDynamic (GetDynamic a) a) => a -> a
removeDynMark x = set (dynamics' . _Wrapped' . _2) Nothing x
