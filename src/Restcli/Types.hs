{-# LANGUAGE DeriveGeneric #-}

module Restcli.Types where

import           Control.Monad.Catch            ( SomeException )
import           Data.Aeson                     ( FromJSON )
import qualified Data.Aeson                    as Aeson
import           Data.ByteString.Char8          ( ByteString )
import qualified Data.ByteString.Lazy.Char8    as LB
import           Data.Char                      ( isAlpha )
import           Data.HashMap.Strict.InsOrd     ( InsOrdHashMap )
import           Data.Text                      ( Text )
import qualified Data.Yaml                     as Yaml
import           GHC.Generics                   ( Generic )
import qualified Network.HTTP.Types            as HTTP
import           Text.URI                       ( URI(..) )

decodeYaml :: FromJSON a => ByteString -> Either Yaml.ParseException a
decodeYaml = Yaml.decodeEither'

------------------------------------------------------------------------
-- API documents.

newtype API = API ReqGroup
    deriving (Eq, Show)

data ReqNode = Req HttpRequest | ReqGroup ReqGroup
    deriving (Eq, Show)

type ReqGroup = InsOrdHashMap Text ReqNode

data HttpRequest = HttpRequest
    { reqMethod :: HTTP.StdMethod
    , reqUrl :: URI
    , reqQuery :: Maybe RequestQuery
    , reqHeaders :: Maybe RequestHeaders
    , reqBody :: Maybe RequestBody
    , reqScript :: Maybe Text
    } deriving (Generic, Eq, Show)

newtype RequestQuery = RequestQuery { unRequestQuery :: HTTP.QueryText }
    deriving (Eq, Show)

newtype RequestHeaders = RequestHeaders { unRequestHeaders :: [HTTP.Header] }
    deriving (Eq, Show)

newtype RequestBody = RequestBody { unRequestBody :: Aeson.Value }
    deriving (Eq, Show)

------------------------------------------------------------------------
-- Env documents.

newtype Env = Env (InsOrdHashMap Text Yaml.Value)
    deriving (Eq, Show)

------------------------------------------------------------------------
-- Abstractions for dynamically working with API.

data APIComponent
    = APIGroup ReqGroup
    | APIRequest HttpRequest
    | APIRequestAttr RequestAttr
    deriving (Eq, Show)

data APIComponentKind
    = GroupKind
    | RequestKind
    | RequestAttrKind RequestAttrKind
    deriving (Eq)

instance Show APIComponentKind where
    show GroupKind               = "Group"
    show RequestKind             = "Request"
    show (RequestAttrKind attrT) = "Request `" ++ show attrT ++ "`"

-- TODO: add script to all these
data RequestAttr
    = ReqMethod HTTP.StdMethod
    | ReqUrl URI
    | ReqQuery (Maybe RequestQuery)
    | ReqHeaders (Maybe RequestHeaders)
    | ReqBody (Maybe RequestBody)
    | ReqScript (Maybe Text)
    deriving (Generic, Eq, Show)

data RequestAttrKind
    = ReqMethodT
    | ReqUrlT
    | ReqQueryT
    | ReqHeadersT
    | ReqBodyT
    | ReqScriptT
    deriving (Eq)

instance Show RequestAttrKind where
    show ReqMethodT  = "method"
    show ReqUrlT     = "url"
    show ReqQueryT   = "query"
    show ReqHeadersT = "headers"
    show ReqBodyT    = "json"
    show ReqScriptT  = "script"

instance Read RequestAttrKind where
    readsPrec _ input =
        let (word, rest) = span isAlpha input
            parsed       = case word of
                "method"  -> Just ReqMethodT
                "url"     -> Just ReqUrlT
                "query"   -> Just ReqQueryT
                "headers" -> Just ReqHeadersT
                "json"    -> Just ReqBodyT
                "script"  -> Just ReqScriptT
                _         -> Nothing
        in  maybe [] (\p -> [(p, rest)]) parsed

getRequestAttr :: RequestAttrKind -> HttpRequest -> RequestAttr
getRequestAttr ReqMethodT  = ReqMethod . reqMethod
getRequestAttr ReqUrlT     = ReqUrl . reqUrl
getRequestAttr ReqQueryT   = ReqQuery . reqQuery
getRequestAttr ReqHeadersT = ReqHeaders . reqHeaders
getRequestAttr ReqBodyT    = ReqBody . reqBody
getRequestAttr ReqScriptT  = ReqScript . reqScript

------------------------------------------------------------------------
-- HTTP responses.

data HttpResponse = HttpResponse
    { resHttpVersion :: HTTP.HttpVersion
    , resStatusCode :: Int
    , resStatusText :: Text
    , resHeaders :: [HTTP.Header]
    , resBody :: LB.ByteString
    , resJSON :: Maybe (Either SomeException Aeson.Value)
    } deriving (Show)
