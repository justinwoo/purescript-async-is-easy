module Main where

import Prelude
import Control.Monad.Aff (Canceler, Aff, liftEff', makeAff, launchAff)
import Control.Monad.Aff.Console (CONSOLE)
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (logShow)
import Control.Monad.Eff.Exception (message, EXCEPTION)
import Control.Monad.Eff.Ref (REF)
import Control.Observable (Subscription, subscribe, free, observable, Observable, OBSERVABLE)
import Control.Observable.Lift (liftAff)
import Control.Parallel.Class (runParallel, parallel)
import Control.XStream (create, addListener, STREAM, Stream, fromAff)
import Data.Array (length)

foreign import foreignCalculateLength :: forall e a.
  Array a ->
  (Int -> Eff e Unit) ->
  Eff e Unit

calculateLengthEff :: forall e a.
  Array a ->
  (Int -> Eff e Unit) ->
  Eff e Unit
calculateLengthEff l s = do
  s (length l)
  pure unit

type Main e = Eff (console :: CONSOLE | e) Unit

mainCallback :: forall e. Main e
mainCallback =
  foreignCalculateLength [1,2,3] (\x -> do
    logShow (x * 2)
  )

mainCallback2 :: forall e. Main e
mainCallback2 =
  foreignCalculateLength [1,2,3] (\x -> do
    calculateLengthEff [4,5,6] (\y -> do
      logShow (x + y)
    )
  )

calculateLengthAff :: forall e a. Array a -> Aff e Int
calculateLengthAff l = makeAff \error success -> foreignCalculateLength l success

calculateLengthAff' :: forall e a. Array a -> Aff e Int
calculateLengthAff' l = makeAff \error success -> do
  success (length l)

calculateLengthAff'' :: forall e a. Array a -> Aff e Int
calculateLengthAff'' l = pure (length l)

type MainAff e = Eff (err :: EXCEPTION, console :: CONSOLE | e) (Canceler (console :: CONSOLE | e))

mainAff :: forall e. MainAff e
mainAff = launchAff do
  x <- calculateLengthAff [1,2,3]
  liftEff' (logShow (x * 2))

mainAff2 :: forall e. MainAff e
mainAff2 = launchAff do
  x <- calculateLengthAff [1,2,3]
  y <- calculateLengthAff' [4,5]
  z <- calculateLengthAff' [6]
  liftEff' (logShow (x + y + z))

mainAff3 :: forall e. MainAff e
mainAff3 = launchAff do
  result <- (*) 2 <$> (calculateLengthAff [1,2,3])
  liftEff' (logShow result)

mainAff4 :: forall e. MainAff e
mainAff4 = launchAff do
  result <- runParallel $ (\a b c -> a + b + c)
    <$> parallel (calculateLengthAff [1,2,3])
    <*> parallel (calculateLengthAff' [4,5])
    <*> parallel (calculateLengthAff'' [6])
  liftEff' (logShow result)

mainAff5 :: forall e. MainAff e
mainAff5 = launchAff do
  let aff = calculateLengthAff [1,2,3]
  result <- runParallel $ (\x y z -> x + y + z)
    <$> parallel aff
    <*> parallel ((_ - 1) <$> aff)
    <*> parallel ((_ - 2) <$> aff)
  liftEff' (logShow result)

calculateLengthObs :: forall e a. Array a -> Eff (observable :: OBSERVABLE | e) (Observable Int)
calculateLengthObs l = liftAff (calculateLengthAff l)

calculateLengthObs' :: forall e a. Array a -> Eff (observable :: OBSERVABLE | e) (Observable Int)
calculateLengthObs' l = observable \sink -> do
  sink.next (length l)
  sink.complete
  free []

calculateLengthObs'' :: forall a. Array a -> Observable Int
calculateLengthObs'' l = pure (length l)

type MainObs e = Eff (observable :: OBSERVABLE, console :: CONSOLE | e) (Subscription (console :: CONSOLE | e))

mainObs :: forall e. MainObs e
mainObs = do
  s <- calculateLengthObs [1,2,3]
  subscribe
    { next : \x -> logShow (x * 2)
    , error: message >>> logShow
    , complete: pure unit
    }
    s

mainObs2 :: forall e. MainObs e
mainObs2 = do
  s <- calculateLengthObs [1,2,3]
  subscribe
    { next : logShow
    , error: message >>> logShow
    , complete: pure unit
    }
    ((*) 2 <$> s)

mainObs3 :: forall e. MainObs e
mainObs3 = do
  s1 <- calculateLengthObs [1,2,3]
  s2 <- calculateLengthObs' [4,5]
  let s3 = calculateLengthObs'' [6]
  subscribe
    { next: logShow
    , error: message >>> logShow
    , complete: pure unit
    }
    ((\x y z -> x + y + z) <$> s1 <*> s2 <*> s3)

calculateLengthXStream :: forall e a. Array a -> Eff (stream :: STREAM, ref :: REF | e) (Stream Int)
calculateLengthXStream l = fromAff (calculateLengthAff l)

calculateLengthXStream' :: forall a e. Array a -> Eff (stream :: STREAM | e) (Stream Int)
calculateLengthXStream' l =
  create
    { start: \o -> do
        o.next (length l)
        o.complete unit
    , stop: const (pure unit)
    }

mainXStream :: forall e.
  Eff
    ( stream :: STREAM
    , ref :: REF
    , console :: CONSOLE
    | e
    )
    Unit
mainXStream = do
  s1 <- calculateLengthXStream [1,2,3]
  s2 <- calculateLengthXStream' [4,5]
  addListener
    { next: logShow
    , error: message >>> logShow
    , complete: const (pure unit)
    }
    ((+) <$> s1 <*> ((+) 1 <$> s2))

main :: forall e.
  Eff
    ( console :: CONSOLE
    , err :: EXCEPTION
    , observable :: OBSERVABLE
    , stream :: STREAM
    , ref :: REF
    | e
    )
    Unit
main = do
  mainCallback
  mainCallback2
  void mainAff
  void mainAff2
  void mainAff3
  void mainAff4
  void mainAff5
  void mainObs
  void mainObs2
  void mainObs3
  mainXStream
