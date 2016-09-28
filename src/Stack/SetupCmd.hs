{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Install GHC/GHCJS and Cabal.
module Stack.SetupCmd
    ( setup
    , setupParser
    , SetupCmdOpts(..)
    ) where

import           Control.Applicative
import           Control.Monad.Catch
import           Control.Monad.IO.Class
import           Control.Monad.Logger
import           Control.Monad.Reader
import           Control.Monad.Trans.Control
import           Data.Monoid
import qualified Data.Text as T
import qualified Options.Applicative as OA
import qualified Options.Applicative.Builder.Extra as OA
import qualified Options.Applicative.Types as OA
import           Network.HTTP.Client
import           Path
import           Prelude -- silence redundant import warnings
import           Stack.Setup
import           Stack.Types.Compiler
import           Stack.Types.Config
import           Stack.Types.Internal
import           Stack.Types.Version

data SetupCmdOpts = SetupCmdOpts
    { scoCompilerVersion :: !(Maybe CompilerVersion)
    , scoForceReinstall  :: !Bool
    , scoUpgradeCabal    :: !Bool
    , scoStackSetupYaml  :: !String
    , scoGHCBindistURL   :: !(Maybe String)
    }

setupParser :: OA.Parser SetupCmdOpts
setupParser = SetupCmdOpts
    <$> OA.optional (OA.argument readVersion
            (OA.metavar "GHC_VERSION" <>
             OA.help ("Version of GHC to install, e.g. 7.10.2. " ++
                      "The default is to install the version implied by the resolver.")))
    <*> OA.boolFlags False
            "reinstall"
            "reinstalling GHC, even if available (incompatible with --system-ghc)"
            OA.idm
    <*> OA.boolFlags False
            "upgrade-cabal"
            "installing the newest version of the Cabal library globally"
            OA.idm
    <*> OA.strOption
            ( OA.long "stack-setup-yaml"
           <> OA.help "Location of the main stack-setup.yaml file"
           <> OA.value defaultStackSetupYaml
           <> OA.showDefault )
    <*> OA.optional (OA.strOption
            (OA.long "ghc-bindist"
           <> OA.metavar "URL"
           <> OA.help "Alternate GHC binary distribution (requires custom --ghc-variant)"))
  where
    readVersion = do
        s <- OA.readerAsk
        case parseCompilerVersion ("ghc-" <> T.pack s) of
            Nothing ->
                case parseCompilerVersion (T.pack s) of
                    Nothing -> OA.readerError $ "Invalid version: " ++ s
                    Just x -> return x
            Just x -> return x

setup
    :: (MonadIO m, MonadLogger m, MonadReader env m, HasConfig env,
        MonadBaseControl IO m, MonadMask m, HasHttpManager env,
        HasGHCVariant env, HasTerminal env, HasReExec env, HasLogLevel env)
    => SetupCmdOpts
    -> CompilerVersion
    -> VersionCheck
    -> Maybe (Path Abs File)
    -> m ()
setup SetupCmdOpts{..} wantedCompiler compilerCheck mstack = do
    Config{..} <- asks getConfig
    mpaths <- fst <$> ensureCompiler SetupOpts
        { soptsInstallIfMissing = True
        , soptsUseSystem = configSystemGHC && not scoForceReinstall
        , soptsWantedCompiler = wantedCompiler
        , soptsCompilerCheck = compilerCheck
        , soptsStackYaml = mstack
        , soptsForceReinstall = scoForceReinstall
        , soptsSanityCheck = True
        , soptsSkipGhcCheck = False
        , soptsSkipMsys = configSkipMsys
        , soptsUpgradeCabal = scoUpgradeCabal
        , soptsResolveMissingGHC = Nothing
        , soptsStackSetupYaml = scoStackSetupYaml
        , soptsGHCBindistURL = scoGHCBindistURL
        }
    let compiler = case wantedCompiler of
            GhcVersion _ -> "GHC"
            GhcjsVersion {} -> "GHCJS"
    case mpaths of
        Nothing -> $logInfo $ "stack will use the " <> compiler <> " on your PATH"
        Just _ -> $logInfo $ "stack will use a sandboxed " <> compiler <> " it installed"
    $logInfo "For more information on paths, see 'stack path' and 'stack exec env'"
    $logInfo $ "To use this " <> compiler <> " and packages outside of a project, consider using:"
    $logInfo "stack ghc, stack ghci, stack runghc, or stack exec"
