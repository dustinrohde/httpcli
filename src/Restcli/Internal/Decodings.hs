{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Restcli.Internal.Decodings
    ()
where

import           Data.Aeson
import           Data.Aeson.Types               ( Parser
                                                , emptyArray
                                                )
import qualified Data.ByteString.Char8         as C
import           Data.Char                      ( toUpper )
import           Data.HashMap.Strict            ( HashMap )
import qualified Data.HashMap.Strict           as Map
import           Data.Text                      ( Text )
import qualified Data.Text                     as T
import           Data.Text.Encoding             ( encodeUtf8 )
import qualified Data.Vector                   as V
import           Data.Void
import qualified Data.Yaml                     as Yaml
import qualified Network.HTTP.Types            as HTTP
import           Text.Read                      ( readEither )
import           Text.URI                       ( URI )
import qualified Text.URI                      as URI
import           Text.Megaparsec                ( Parsec
                                                , runParser
                                                )

import           Restcli.Internal.ParseHeaders  ( parseHeaders )
import           Restcli.Types

instance FromJSON Request where
    parseJSON = withObject "request" $ \v -> do
        reqMethod  <- v .: "method" >>= parseJSON
        reqUrl     <- v .: "url" >>= parseJSON
        reqQuery   <- v .:? "query" .!= Null >>= parseJSON
        reqHeaders <- v .:? "headers" .!= Null >>= parseJSON
        reqBody    <- v .:? "json" .!= Null >>= parseJSON
        return Request { .. }

instance FromJSON HTTP.StdMethod where
    parseJSON = withText "method" $ \method ->
        case readEither . map toUpper $ T.unpack method of
            Left  err    -> errReqField method "method" ""
            Right method -> return method

instance FromJSON URI where
    parseJSON = withText "uri" $ \uri ->
        case runParser (URI.parser :: Parsec Void Text URI) "" uri of
            Left  err -> errReqField uri "url" (show err)
            Right val -> return val

instance FromJSON RequestQuery where
    -- TODO: allow for no-value keys
    parseJSON =
        withArray "query"
            $ fmap (Query . concatMap Map.toList . V.toList)
            . mapM parseQueryItems
      where
        parseQueryItems = withObject "query item" $ mapM parseQueryVal
        parseQueryVal   = withText "query item value" (return . Just)

instance FromJSON RequestHeaders where
    parseJSON = withText "headers" $ \headers ->
        -- TODO: write a new, much more lenient parser that auto-escapes bad chars,
        -- auto-quotes header values, and allows multiple newlines between headers.
        case runParser parseHeaders "" $ encodeUtf8 headers of
            Left  err -> errReqField headers "headers" (show err)
            Right val -> return . Headers $ val

instance FromJSON RequestBody where
    -- TODO: allow for other body types
    parseJSON = withText "json" $ \body ->
        case Yaml.decodeEither' $ encodeUtf8 body :: YamlParser Value of
            Left  err -> errReqField body "json" (show err)
            Right val -> return . ReqBodyJson $ val


errReqField :: Text -> String -> String -> Parser a
errReqField actual field msg = fail $ before ++ base ++ after
  where
    base   = "invalid value for request `" ++ field ++ "`"
    before = if T.null actual then "" else "'" ++ T.unpack actual ++ "': "
    after  = if null msg then "" else ": " ++ msg
