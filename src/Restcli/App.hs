module Restcli.App where

import           Control.Exception
import           Control.Monad.Reader
import           Control.Monad.State
import           Data.ByteString.Char8          ( ByteString )
import qualified Data.ByteString.Char8         as B
import qualified Data.HashMap.Strict.InsOrd    as Map
import           Data.Text                      ( Text )
import qualified Data.Text                     as T
import qualified Data.Text.Lazy                as LT
import qualified Data.Yaml                     as Yaml
import           Text.Mustache                  ( Template )
import qualified Text.Pretty.Simple            as PP

import           Restcli.Api
import           Restcli.Cli
import           Restcli.Data.Encoding
import           Restcli.Error
import           Restcli.Requests
import           Restcli.Types
import           Restcli.Utils                  ( unsnoc )

type App = ReaderT Options (StateT AppState IO)

data AppState = AppState
    { appAPI :: API
    , appEnv :: Env
    , appAPITemplate :: Template
    } deriving (Show)

-- | Run the main program.
run :: IO ()
run = runApp $ dispatch >>= liftIO . B.putStrLn

-- | Run the main program with custom Options and AppState, ignoring the
-- commandline.
runWith :: Options -> AppState -> IO ()
runWith = runAppWith $ dispatch >>= liftIO . B.putStrLn

-- | Run the given App with context obtained from the commandline.
--
-- 1. Obtains Options by parsing the commandline.
-- 2. Creates an initial AppState by reading Template & Env files and compiling
--    an API object from them.
-- 3. Calls `runAppWith` with the Options and AppState.
runApp :: App a -> IO a
runApp app = do
    opts <- parseCli
    tmpl <- readApiTemplate $ optApiFile opts
    env  <- case optEnvFile opts of
        Just filePath -> readEnv filePath
        Nothing       -> return Map.empty

    case parseAPI tmpl env of
        Left err -> fail $ displayException err
        Right api ->
            -- <DEBUG>
            let section name = putStrLn $ unlines [replicate 25 '-', name]
            in
                section "API"
                >> B.putStrLn (Yaml.encode api)
                >> section "ENV"
                >> B.putStrLn (Yaml.encode env)
                >> section "PROGRAM OUTPUT"
                >> -- </DEBUG>
                   runAppWith
                       app
                       opts
                       AppState { appAPI         = api
                                , appEnv         = env
                                , appAPITemplate = tmpl
                                }

-- | Run the given App with the given Options and AppState.
runAppWith :: App a -> Options -> AppState -> IO a
runAppWith app opts = evalStateT (runReaderT app opts)

-- | Execute the App's command, found in its Options.
dispatch :: App ByteString
dispatch = ask >>= \opts -> case optCommand opts of
    Run  path -> cmdRun $ toText path
    View path -> cmdView $ toText path
    where toText = map T.pack

-- | Execute the `run` command.
cmdRun :: [Text] -> App ByteString
cmdRun path = do
    api <- gets appAPI
    let (groupKeys, reqKey) = unsnoc path
    case getApiRequest groupKeys reqKey api of
        Left  err -> fail $ displayException err
        Right req -> liftIO $ B.pack . pshow <$> sendRequest req

-- | Execute the `view` command.
cmdView :: [Text] -> App ByteString
cmdView path = do
    api <- gets appAPI
    case getApiComponent' path api of
        Right (APIGroup       group) -> return $ Yaml.encode group
        Right (APIRequest     req  ) -> return $ Yaml.encode req
        Right (APIRequestAttr attr ) -> return $ Yaml.encode attr
        Left  err                    -> fail $ displayException err

-- | Reload the App's Env.
reloadEnv :: App Env
reloadEnv = do
    filePath <- asks optEnvFile
    case filePath of
        Nothing       -> gets appEnv
        Just filePath -> do
            env <- liftIO $ readEnv filePath
            modify $ \appState -> appState { appEnv = env }
            return env

-- | Reload the App's API Template.
reloadAPITemplate :: App Template
reloadAPITemplate = do
    tmpl <- asks optApiFile >>= liftIO . readApiTemplate
    modify $ \appState -> appState { appAPITemplate = tmpl }
    return tmpl

-- | Reload the App's API, compiling it from its Template and Env.
reloadAPI :: App API
reloadAPI = do
    AppState { appEnv = env, appAPITemplate = tmpl } <- get
    case parseAPI tmpl env of
        Left  err -> fail $ displayException err
        Right api -> do
            modify $ \appState -> appState { appAPI = api }
            return api

pprint :: Show a => a -> IO ()
pprint = PP.pPrintOpt PP.NoCheckColorTty prettyOptions

pshow :: Show a => a -> String
pshow = LT.unpack . PP.pShowOpt prettyOptions

prettyOptions :: PP.OutputOptions
prettyOptions =
    PP.defaultOutputOptionsNoColor { PP.outputOptionsIndentAmount = 2 }
