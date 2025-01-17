module NammaDSL.Generator.Haskell.Servant (generateServantAPI, handlerSignature, handlerFunctionText) where

import Control.Lens ((^.))
import Data.List (intercalate, nub)
import Data.List.Extra (snoc)
import qualified Data.Text as T
import Kernel.Prelude hiding (replicateM)
import NammaDSL.DSL.Syntax.API
import NammaDSL.Generator.Haskell.Common (apiAuthTypeMapperServant, checkForPackageOverrides)
import NammaDSL.GeneratorCore
import NammaDSL.Utils

generateServantAPI :: Apis -> Code
generateServantAPI input =
  generateCode generatorInput
  where
    packageOverride :: [String] -> [String]
    packageOverride = checkForPackageOverrides (input ^. importPackageOverrides)

    generatorInput :: GeneratorInput
    generatorInput =
      GeneratorInput
        { _ghcOptions = ["-Wno-orphans", "-Wno-unused-imports"],
          _extensions = [],
          _moduleNm = "API.Action.UI." <> T.unpack (_moduleName input),
          _simpleImports = packageOverride allSimpleImports,
          _qualifiedImports = packageOverride allQualifiedImports,
          _codeBody = generateCodeBody mkCodeBody input
        }
    defaultQualifiedImport :: [String]
    defaultQualifiedImport =
      [ "Domain.Types.Person",
        "Kernel.Prelude",
        "Control.Lens",
        "Domain.Types.Merchant",
        "Environment",
        "Kernel.Types.Id"
      ]

    allQualifiedImports :: [String]
    allQualifiedImports =
      [ "Domain.Action.UI."
          <> T.unpack (_moduleName input)
          <> " as "
          <> "Domain.Action.UI."
          <> T.unpack (_moduleName input)
      ]
        <> ( nub $
               defaultQualifiedImport
                 <> ( figureOutImports
                        (T.unpack <$> concatMap handlerSignature (_apis input))
                    )
           )

    allSimpleImports :: [String]
    allSimpleImports =
      [ "EulerHS.Prelude",
        "Servant",
        "Tools.Auth",
        "Kernel.Utils.Common",
        "API.Types.UI."
          <> T.unpack (_moduleName input)
          <> " ("
          <> intercalate ", " (map (T.unpack . fst) (input ^. apiTypes . types))
          <> ")"
      ]
        <> ["Storage.Beam.SystemConfigs ()" | ifNotDashboard]

    ifNotDashboard :: Bool
    ifNotDashboard =
      any
        ( \authType' -> do
            case authType' of
              Just (DashboardAuth _) -> False
              _ -> True
        )
        (map _authType $ _apis input)

mkCodeBody :: ApisM ()
mkCodeBody = do
  input <- ask
  let allApis = _apis input
      moduleName' = _moduleName input
      seperator = onNewLine (tellM " :<|> ")
      handlerFunctionText' = tellM . T.unpack . handlerFunctionText
  onNewLine $ do
    tellM "type API = "
    onNewLine $ withSpace $ intercalateA seperator (map apiTTToText allApis)
  onNewLine $ do
    tellM "handler  :: Environment.FlowServer API"
    onNewLine $ tellM "handler = "
    withSpace $ intercalateA seperator (map handlerFunctionText' allApis)
  onNewLine $ intercalateA newLine (map (handlerFunctionDef moduleName') allApis)
  where
    isAuthPresent :: ApiTT -> Bool
    isAuthPresent apiT = case _authType apiT of
      Just NoAuth -> False
      _ -> True

    isDashboardAuth :: ApiTT -> Bool
    isDashboardAuth apiT = case _authType apiT of
      Just (DashboardAuth _) -> True
      _ -> False

    generateParams :: Bool -> Bool -> Int -> Int -> Text
    generateParams _ _ _ 0 = ""
    generateParams isAuth isbackParam mx n =
      ( if mx == n && isbackParam && isAuth
          then " (Control.Lens.over Control.Lens._1 Kernel.Prelude.Just a" <> T.pack (show n) <> ")"
          else " a" <> T.pack (show n)
      )
        <> generateParams isAuth isbackParam mx (n - 1)

    handlerFunctionDef :: Text -> ApiTT -> ApisM ()
    handlerFunctionDef moduleName' apiT =
      let functionName = handlerFunctionText apiT
          allTypes = handlerSignature apiT
          showType = case filter (/= T.empty) (init allTypes) of
            [] -> T.empty
            ty -> T.intercalate " -> " ty
          handlerTypes = showType <> (if length allTypes > 1 then " -> " else " ") <> "Environment.FlowHandler " <> last allTypes
       in tellM $
            T.unpack $
              functionName <> maybe " :: " (\x -> " :: " <> x <> " -> ") (apiAuthTypeMapperServant apiT) <> handlerTypes
                <> "\n"
                <> functionName
                <> generateParams (isAuthPresent apiT && not (isDashboardAuth apiT)) False (length allTypes) (if isAuthPresent apiT then length allTypes else length allTypes - 1)
                <> generateWithFlowHandlerAPI (isDashboardAuth apiT)
                <> "Domain.Action.UI."
                <> moduleName'
                <> "."
                <> functionName
                <> generateParams (isAuthPresent apiT && not (isDashboardAuth apiT)) True (length allTypes) (if isAuthPresent apiT then length allTypes else length allTypes - 1)
                <> "\n"

generateWithFlowHandlerAPI :: Bool -> Text
generateWithFlowHandlerAPI isDashboardAuth = do
  case isDashboardAuth of
    True -> " = withFlowHandlerAPI' $ "
    False -> " = withFlowHandlerAPI $ "

apiTTToText :: ApiTT -> ApisM ()
apiTTToText apiTT =
  let urlPartsText = map urlPartToText (_urlParts apiTT)
      apiTypeText = apiTypeToText (_apiType apiTT)
      apiReqText = apiReqToText (_apiReqType apiTT)
      apiResText = apiResToText (_apiResType apiTT)
      headerText = map headerToText (_header apiTT)
   in tellM $
        T.unpack $
          addAuthToApi (_authType apiTT) (T.concat urlPartsText <> T.concat headerText <> apiReqText <> " :> " <> apiTypeText <> apiResText)
  where
    addAuthToApi :: Maybe AuthType -> Text -> Text
    addAuthToApi authtype apiDef = case authtype of
      Just AdminTokenAuth -> "AdminTokenAuth" <> apiDef
      Just (TokenAuth _) -> "TokenAuth" <> apiDef
      Just (DashboardAuth dashboardAuthType) -> "DashboardAuth '" <> T.pack (show dashboardAuthType) <> apiDef
      Just NoAuth -> fromMaybe apiDef (T.stripPrefix " :>" apiDef)
      Nothing -> "TokenAuth" <> apiDef

    urlPartToText :: UrlParts -> Text
    urlPartToText (UnitPath path) = " :> \"" <> path <> "\""
    urlPartToText (Capture path ty) = " :> Capture \"" <> path <> "\" (" <> ty <> ")"
    urlPartToText (QueryParam path ty isMandatory) =
      " :> " <> (if isMandatory then "Mandatory" else "") <> "QueryParam \"" <> path <> "\" (" <> ty <> ")"

    apiReqToText :: Maybe ApiReq -> Text
    apiReqToText Nothing = ""
    apiReqToText (Just (ApiReq ty frmt)) = " :> ReqBody '[" <> frmt <> "] " <> ty

    apiResToText :: ApiRes -> Text
    apiResToText (ApiRes name ty) = " '[" <> ty <> "] " <> name

    headerToText :: HeaderType -> Text
    headerToText (Header name ty) = " :> Header \"" <> name <> "\" " <> ty

handlerFunctionText :: ApiTT -> Text
handlerFunctionText apiTT =
  let apiTypeText = T.toLower $ apiTypeToText (_apiType apiTT)
      urlPartsText = map urlPartToName (_urlParts apiTT)
   in apiTypeText <> T.intercalate "" (filter (/= T.empty) urlPartsText)
  where
    urlPartToName :: UrlParts -> Text
    urlPartToName (UnitPath name) = (T.toUpper . T.singleton . T.head) name <> T.tail name
    urlPartToName _ = ""

handlerSignature :: ApiTT -> [Text]
handlerSignature input =
  let urlTypeText = map urlToText (_urlParts input)
      headerTypeText = map (\(Header _ ty) -> ty) (_header input)
      reqTypeText = reqTypeToText $ _apiReqType input
      resTypeText = (\(ApiRes ty _) -> ty) $ _apiResType input
   in filter (/= T.empty) (snoc (snoc (urlTypeText ++ headerTypeText) reqTypeText) resTypeText)
  where
    urlToText :: UrlParts -> Text
    urlToText (Capture _ ty) = ty
    urlToText (QueryParam _ ty isMandatory) = do
      if isMandatory
        then ty
        else "Kernel.Prelude.Maybe (" <> ty <> ")"
    urlToText _ = ""

    reqTypeToText :: Maybe ApiReq -> Text
    reqTypeToText Nothing = ""
    reqTypeToText (Just (ApiReq ty _)) = ty
