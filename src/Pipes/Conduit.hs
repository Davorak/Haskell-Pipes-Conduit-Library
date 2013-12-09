{-# language OverloadedStrings #-}

module Pipes.Conduit where

import Control.Monad

import Pipes
import qualified Pipes.Prelude as P

import qualified Data.Conduit as C
import qualified Data.Conduit.List as CL


{- | Await chunks from pipe then yield it to conduit lower on the monad 
transformer stack.
-}
awaitPipeLiftYieldConduit
  :: Monad m => Proxy () (Maybe o) y' y (C.ConduitM i o m) ()
awaitPipeLiftYieldConduit = go
  where
    go = do
        x0 <- await
        case x0 of
            Nothing -> return ()
            Just x  -> lift (C.yield x) >> go

{- | Await chunks from pipe then yield it to a conduit higher up on the monad 
transformer stack.
-}
liftAwaitPipeYieldConduit
  :: Monad m => C.ConduitM i o (Proxy () (Maybe o) y' y m) ()
liftAwaitPipeYieldConduit = go
  where
    go = do
        x0 <- lift await
        case x0 of
            Nothing -> return ()
            Just x  -> C.yield x >> go

{- | Await chunks from conduit then yield it to a pipe lower down on the 
monad transformer stack.
-}
awaitConduitLiftYieldPipe
  :: Monad m => C.ConduitM a o (Proxy x' x () a m) ()
awaitConduitLiftYieldPipe = go
  where
    go = do
        x0 <- C.await
        case x0 of
            Nothing -> return ()
            Just x  -> lift (yield x) >> go

{- | Await chunks from conduit then yield it to a pipe higher up on the monad
transformer stack.
-}
liftAwaitConduitYieldPipe
  :: Monad m => Proxy x' x () a (C.ConduitM a o m) ()
liftAwaitConduitYieldPipe = go
  where
    go = do
        x0 <- lift C.await
        case x0 of
            Nothing -> return ()
            Just x  -> yield x >> go

catC :: Monad m => C.ConduitM o o m ()
catC = go
  where
    go = do
        x0 <- C.await
        case x0 of
            Nothing -> return ()
            Just x  -> C.yield x >> go

-- taken from Pipes.Parse-1.0.0
{-| Guard a pipe from terminating by wrapping every output in 'Just' and ending
    with a never-ending stream of 'Nothing's.
    
    Conduits use a stream of Nothing to indicate that the upstream conduit
    has shutdown. When using conduits in a pipeline you need to by into this
    model to get full conduit functionality. For example consider embeding
    a simple conduit to take pairs of upstream values and yeild them down 
    steam.

    takePairs = liftAwaitPipeYieldConduit 
            C.$= CL.sequence (CL.take 2) 
            C.$$ awaitConduitLiftYieldPipe

    If the upstream pipeline does not return an infinite stream of Nothing then
    the the CL.take can not yield its left overs before the pipe shuts down.

    > runEffect  $ each [1..9] >-> P.map Just >-> takePairs >-> P.print
    [1,2]
    [3,4]
    [5,6]
    [7,8]

    However if you 'wrap' the upstream pipeline then you CL.take is notified
    when up stremam has shutdown the ouput is:

    >runEffect  $ wrap (each [1..9]) >-> conduitEx1 >-> P.print
    [1,2]
    [3,4]
    [5,6]
    [7,8]
    [9]

    Just like in conduit:

    > CL.sourceList [1..9] C.$= CL.sequence (CL.take 2) 
                           C.$$ CL.mapM_ (liftIO . print)
    [1,2]
    [3,4]
    [5,6]
    [7,8]
    [9]

-}
-- todo use Pipe' ? Pipe' is Pipe or Producer
wrap
  :: Monad m =>
       Proxy a' a () b m r -> Proxy a' a () (Maybe b) m r
wrap p = do
    p >-> P.map Just
    forever $ yield Nothing


pipeProducerToConduit
  :: Monad m => Producer a m () 
             -> C.Producer m a
pipeProducerToConduit p = 
    runEffect $ wrap (hoist lift p)  
        >-> awaitPipeLiftYieldConduit
