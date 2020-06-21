{-# LANGUAGE DeriveGeneric #-}

module Restcli.Types where

import qualified Data.Aeson                    as Aeson
import           Data.Char                      ( isAlpha )
import           Data.HashMap.Strict            ( HashMap )
import           Data.Text                      ( Text )
import qualified Data.Yaml                     as Yaml
import           GHC.Generics                   ( Generic )
import qualified Network.HTTP.Types            as HTTP
import           Text.Read
import           Text.URI                       ( URI(..) )

newtype API = API ReqGroup
    deriving (Generic, Eq, Show)

data ReqNode = Req Request | ReqGroup ReqGroup
    deriving (Eq, Show)

type ReqGroup = HashMap Text ReqNode

data Request = Request
    { reqMethod :: HTTP.StdMethod
    , reqUrl :: URI
    , reqQuery :: Maybe RequestQuery
    , reqHeaders :: Maybe RequestHeaders
    , reqBody :: Maybe RequestBody
    } deriving (Generic, Eq, Show)

newtype RequestQuery = Query HTTP.QueryText deriving (Eq, Show)

newtype RequestHeaders = Headers HTTP.RequestHeaders deriving (Eq, Show)

newtype RequestBody = ReqBodyJson Aeson.Value
    deriving (Eq, Show)

data RequestAttr
    = ReqMethod HTTP.StdMethod
    | ReqUrl URI
    | ReqQuery (Maybe RequestQuery)
    | ReqHeaders (Maybe RequestHeaders)
    | ReqBody (Maybe RequestBody)
    deriving (Generic, Eq, Show)

data APIComponent
    = APIGroup ReqGroup
    | APIRequest Request
    | APIRequestAttr RequestAttr
    deriving (Eq, Show)

data APIComponentKind
    = GroupKind
    | RequestKind
    | RequestAttrKind RequestComponent
    deriving (Eq)

instance Show APIComponentKind where
    show GroupKind               = "Group"
    show RequestKind             = "Request"
    show (RequestAttrKind attrT) = "Request '" ++ show attrT ++ "'"

data RequestComponent
    = ReqMethodT
    | ReqUrlT
    | ReqQueryT
    | ReqHeadersT
    | ReqBodyT
    deriving (Eq)

instance Show RequestComponent where
    show ReqMethodT  = "method"
    show ReqUrlT     = "url"
    show ReqQueryT   = "query"
    show ReqHeadersT = "headers"
    show ReqBodyT    = "json"

instance Read RequestComponent where
    readsPrec _ input =
        let (word, rest) = span isAlpha input
            parsed       = case word of
                "method"  -> Just ReqMethodT
                "url"     -> Just ReqUrlT
                "query"   -> Just ReqQueryT
                "headers" -> Just ReqHeadersT
                "json"    -> Just ReqBodyT
                _         -> Nothing
        in  maybe [] (\p -> [(p, rest)]) parsed

getRequestAttr :: RequestComponent -> Request -> RequestAttr
getRequestAttr ReqMethodT  = ReqMethod . reqMethod
getRequestAttr ReqUrlT     = ReqUrl . reqUrl
getRequestAttr ReqQueryT   = ReqQuery . reqQuery
getRequestAttr ReqHeadersT = ReqHeaders . reqHeaders
getRequestAttr ReqBodyT    = ReqBody . reqBody

type Env = HashMap Text Yaml.Value

type YamlParser = Either Yaml.ParseException
