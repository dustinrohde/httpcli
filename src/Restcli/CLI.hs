{-# LANGUAGE ApplicativeDo #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE RecordWildCards #-}

module Restcli.CLI where

import           Control.Applicative            ( optional )
import           Data.List.Split                ( splitOn )
import           Data.Semigroup                 ( (<>) )
import           Data.String                    ( IsString
                                                , fromString
                                                )
import           Options.Applicative
import           Options.Applicative.Types      ( readerAsk )
import           System.Environment
import           System.FilePath                ( joinPath )

data Options = Options
    { optCommand :: Command
    , optAPIFile :: FilePath
    , optEnvFile :: Maybe FilePath
    , optSave :: Bool
    } deriving (Eq, Show)

data Command
    = CmdRun { cmdRunPath :: [String] }
    | CmdView { cmdViewPath :: [String] }
    | CmdEnv { cmdEnvPath :: Maybe String, cmdEnvValue :: Maybe String }
    | CmdRepl { cmdReplHistFile :: Maybe FilePath }
    deriving (Eq, Show)

type Environ = [(String, String)]

progName :: String
progName = "httpcli"

parseArgs :: Environ -> IO Options
parseArgs = execParser . parserInfo

parseArgsPure :: [String] -> Environ -> ParserResult Options
parseArgsPure argv environ = execParserPure parserPrefs
                                            (parserInfo environ)
                                            argv
  where parserPrefs = prefs $ showHelpOnEmpty <> showHelpOnError

parserInfo :: Environ -> ParserInfo Options
parserInfo environ = info
  (parser environ <**> helper)
  (fullDesc <> header
    (progName ++ " - a command-line HTTP client for API development")
  )

parser :: Environ -> Parser Options
parser environ = do
  optCommand <- (subparser . foldMap mkCommand)
    [ ( "run"
      , "run a request"
      , CmdRun
        <$> (splitOn "." <$> argument
              nonEmptyStr
              (metavar "REQUEST" <> help "name of the request to run in the API"
              )
            )
      )
    , ( "view"
      , "inspect a group, request, or request attribute"
      , CmdView
        <$> (splitOn "." <$> argument
              nonEmptyStr
              (  metavar "ITEM"
              <> help
                   "the name of a group, request, or request attribute in the API spec"
              )
            )
      )
    , ( "env"
      , "view or update the Env"
      , CmdEnv
      <$> optional
            (argument nonEmptyStr (metavar "KEY" <> help "a key in the Env"))
      <*> optional
            (argument str
                      (metavar "VALUE" <> help "a value to assign to the key")
            )
      )
    , ( "repl"
      , "start an interactive prompt"
      , CmdRepl <$> option
        maybeStr
        (  long "histfile"
        <> short 'H'
        <> value (Just "")
        <> help
             "File where command history is saved.\
            \ Pass an empty value (e.g. \"\") to disable this feature."
        <> showDefaultWith
             (const $ joinPath ["$XDG_CACHE_HOME", progName, "history"])
        )
      )
    ]
  optAPIFile <- option
    nonEmptyStr
    (  long "api"
    <> short 'a'
    <> envvar "HTTPCLI_API" environ
    <> metavar "PATH"
    <> help "API spec file"
    )
  optEnvFile <- optional $ option
    nonEmptyStr
    (  long "env"
    <> short 'e'
    <> envvar "HTTPCLI_ENV" environ
    <> metavar "PATH"
    <> help "Environment file"
    )
  optSave <- switch
    (long "save" <> short 's' <> help
      "save changes made to the Environment from request scripts"
    )
  pure Options { .. }
 where
  mkCommand (name, desc, parser) =
    command name (info (parser <**> helper) (progDesc desc))

nonEmptyStr :: IsString s => ReadM s
nonEmptyStr = eitherReader $ \case
  "" -> Left "invalid argument: empty string"
  s  -> Right $ fromString s

maybeStr :: IsString s => ReadM (Maybe s)
maybeStr = strToMaybe <$> readerAsk
 where
  strToMaybe "" = Nothing
  strToMaybe s  = Just (fromString s)

envvar :: (HasValue f, IsString a) => String -> Environ -> Mod f a
envvar key environ = valueMod <> showDefaultMod
 where
  valueMod       = maybe idm (value . fromString) $ lookup key environ
  showDefaultMod = showDefaultWith $ const ('$' : key)
