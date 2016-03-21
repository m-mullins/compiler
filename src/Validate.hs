{-# OPTIONS_GHC -Wall #-}
module Validate (module') where

import Prelude hiding (init)
import Control.Monad (foldM, when)
import qualified Data.Map as Map
import qualified Data.Maybe as Maybe
import qualified Data.Set as Set
import qualified Data.Foldable as F
import qualified Data.Traversable as T

import AST.Expression.General as Expr
import qualified AST.Effects as Effects
import qualified AST.Expression.Source as Source
import qualified AST.Expression.Valid as Valid
import qualified AST.Declaration as D
import qualified AST.Module as Module
import qualified AST.Module.Name as ModuleName
import qualified AST.Pattern as Pattern
import qualified AST.Type as Type
import qualified Elm.Compiler.Imports as Imports
import qualified Elm.Package as Package
import Elm.Utils ((|>))
import qualified Reporting.Annotation as A
import qualified Reporting.Error.Syntax as Error
import qualified Reporting.Region as R
import qualified Reporting.Result as Result



-- MODULES


module' :: Module.Source -> Result.Result wrn Error.Error Module.Valid
module' (Module.Module name path info) =
  let
    (ModuleName.Canonical pkgName _) =
      name

    (Module.Source tag settings docs exports imports decls) =
      info
  in
    do  (ValidStuff foreigns structure) <- validateDecls decls

        validEffects <- validateEffects tag settings foreigns (D._defs structure)

        return $ Module.Module name path $
          Module.Valid docs exports (addDefaults pkgName imports) structure validEffects



-- IMPORTS


addDefaults
  :: Package.Name
  -> [Module.UserImport]
  -> ([Module.DefaultImport], [Module.UserImport])
addDefaults pkgName imports =
  flip (,) imports $
    if pkgName == Package.coreName then
      []

    else
      Imports.defaults



-- EFFECTS


validateEffects
  :: Module.SourceTag
  -> Module.SourceSettings
  -> [A.Commented Effects.ForeignRaw]
  -> [A.Commented Valid.Def]
  -> Result.Result wrn Error.Error Effects.Raw
validateEffects tag settings@(A.A _ pairs) foreigns validDefs =
  case tag of
    Module.Normal ->
      do  noSettings Error.SettingsOnNormalModule settings
          noForeigns foreigns
          return Effects.None

    Module.Foreign _ ->
      do  noSettings Error.SettingsOnForeignModule settings
          return (Effects.Foreign foreigns)

    Module.Effect tagRegion ->
      let
        collectSettings (A.A region setting, userValue) dict =
          Map.insertWith (++) setting [(region, userValue)] dict

        settingsDict =
          foldr collectSettings Map.empty pairs
      in
        do  noForeigns foreigns
            managerType <- toManagerType tagRegion settingsDict
            (r0, r1, r2) <- checkManager tagRegion managerType validDefs
            return (Effects.Manager (Effects.Info tagRegion r0 r1 r2 managerType))


noSettings
  :: Error.Error
  -> Module.SourceSettings
  -> Result.Result wrn Error.Error ()
noSettings errorMsg (A.A region settings) =
  case settings of
    [] ->
      Result.ok ()

    _ : _ ->
      Result.throw region errorMsg


noForeigns :: [A.Commented Effects.ForeignRaw] -> Result.Result wrn Error.Error ()
noForeigns foreigns =
  case foreigns of
    [] ->
      Result.ok ()

    _ : _ ->
      let
        toError (A.A (region, _) (Effects.ForeignRaw name _)) =
          A.A region (Error.UnexpectedForeign name)
      in
        Result.throwMany (map toError foreigns)


toManagerType
  :: R.Region
  -> Map.Map String [(R.Region, A.Located String)]
  -> Result.Result wrn Error.Error Effects.ManagerType
toManagerType tagRegion settingsDict =
  let
    toErrors name entries =
      map (\entry -> A.A (fst entry) (Error.BadSettingOnEffectModule name)) entries

    errors =
      settingsDict
        |> Map.delete "command"
        |> Map.delete "subscription"
        |> Map.mapWithKey toErrors
        |> Map.elems
        |> concat
  in
    do  when (not (null errors)) (Result.throwMany errors)
        maybeEffects <-
          (,) <$> extractOne "command" settingsDict
              <*> extractOne "subscription" settingsDict

        -- TODO check that cmd and sub types exist?
        case maybeEffects of
          (Nothing, Nothing) ->
            Result.throw tagRegion Error.NoSettingsOnEffectModule

          (Just cmd, Nothing) ->
            return (Effects.CmdManager cmd)

          (Nothing, Just sub) ->
            return (Effects.SubManager sub)

          (Just cmd, Just sub) ->
            return (Effects.FxManager cmd sub)


extractOne
  :: String
  -> Map.Map String [(R.Region, A.Located String)]
  -> Result.Result w Error.Error (Maybe (A.Located String))
extractOne name settingsDict =
  case Map.lookup name settingsDict of
    Nothing ->
      return Nothing

    Just [] ->
      error "Empty lists should never be added to the dictionary of effect module settings."

    Just [(_, userType)] ->
      return (Just userType)

    Just ((region, _) : _) ->
      Result.throw region (Error.DuplicateSettingOnEffectModule name)



-- CHECK EFFECT MANAGER


checkManager
  :: R.Region
  -> Effects.ManagerType
  -> [A.Commented Valid.Def]
  -> Result.Result w Error.Error (R.Region, R.Region, R.Region)
checkManager tagRegion managerType validDefs =
  let
    regionDict =
      Map.fromList (Maybe.mapMaybe getSimpleDefRegion validDefs)
  in
  const (,,)
    <$> requireMaps tagRegion regionDict managerType
    <*> requireRegion tagRegion regionDict "init"
    <*> requireRegion tagRegion regionDict "onEffects"
    <*> requireRegion tagRegion regionDict "onSelfMsg"


getSimpleDefRegion :: A.Commented Valid.Def -> Maybe (String, R.Region)
getSimpleDefRegion decl =
  case decl of
    A.A (region, _) (Valid.Def (A.A _ (Pattern.Var name)) _ _) ->
      Just (name, region)

    _ ->
      Nothing


requireMaps
  :: R.Region
  -> Map.Map String R.Region
  -> Effects.ManagerType
  -> Result.Result w Error.Error ()
requireMaps tagRegion regionDict managerType =
  let
    check name =
      when (Map.notMember name regionDict) $
        Result.throw tagRegion (Error.MissingManagerOnEffectModule name)
  in
  case managerType of
    Effects.CmdManager _ ->
      check "cmdMap"

    Effects.SubManager _ ->
      check "subMap"

    Effects.FxManager _ _ ->
      check "cmdMap" <* check "subMap"


requireRegion
  :: R.Region
  -> Map.Map String R.Region
  -> String
  -> Result.Result w Error.Error R.Region
requireRegion tagRegion regionDict name =
  case Map.lookup name regionDict of
    Just region ->
      return region

    Nothing ->
      Result.throw tagRegion (Error.MissingManagerOnEffectModule name)



-- COLLAPSE COMMENTS


collapseComments :: [D.CommentOr (A.Located a)] -> Result.Result wrn Error.Error [A.Commented a]
collapseComments listWithComments =
  case listWithComments of
    [] ->
      Result.ok []

    D.Comment (A.A _ msg) : D.Whatever (A.A region a) : rest ->
      let
        entry =
          A.A (region, Just msg) a
      in
        fmap (entry:) (collapseComments rest)

    D.Comment (A.A region _) : rest ->
      collapseComments rest
        <* Result.throw region Error.CommentOnNothing


    D.Whatever (A.A region a) : rest ->
      let
        entry =
          A.A (region, Nothing) a
      in
        fmap (entry:) (collapseComments rest)



-- VALIDATE STRUCTURED SOURCE


validateDecls :: [D.Source] -> Result.Result wrn Error.Error ValidStuff
validateDecls sourceDecls =
  do  rawDecls <- collapseComments sourceDecls

      validStuff <- validateRawDecls rawDecls

      let (D.Decls _ unions aliases _) = _structure validStuff

      return validStuff
        <* F.traverse_ checkTypeVarsInUnion unions
        <* F.traverse_ checkTypeVarsInAlias aliases
        <* checkDuplicates validStuff



-- VALIDATE DECLARATIONS


data ValidStuff =
  ValidStuff
    { _foreigns :: [A.Commented Effects.ForeignRaw]
    , _structure :: D.Valid
    }


validateRawDecls :: [A.Commented D.Raw] -> Result.Result wrn Error.Error ValidStuff
validateRawDecls commentedDecls =
  vrdHelp commentedDecls [] (D.Decls [] [] [] [])


vrdHelp
  :: [A.Commented D.Raw]
  -> [A.Commented Effects.ForeignRaw]
  -> D.Valid
  -> Result.Result wrn Error.Error ValidStuff
vrdHelp commentedDecls foreigns structure =
  case commentedDecls of
    [] ->
      Result.ok (ValidStuff foreigns structure)

    A.A ann decl : rest ->
      case decl of
        D.Union (D.Type name tvars ctors) ->
          vrdHelp rest foreigns (D.addUnion (A.A ann (D.Type name tvars ctors)) structure)

        D.Alias (D.Type name tvars alias) ->
          vrdHelp rest foreigns (D.addAlias (A.A ann (D.Type name tvars alias)) structure)

        D.Fixity fixity ->
          vrdHelp rest foreigns (D.addInfix fixity structure)

        D.Def (A.A region def) ->
          vrdDefHelp rest (A.A (region, snd ann) def) foreigns structure

        D.Foreign name tipe ->
          vrdHelp rest (A.A ann (Effects.ForeignRaw name tipe) : foreigns) structure


vrdDefHelp
  :: [A.Commented D.Raw]
  -> A.Commented Source.Def'
  -> [A.Commented Effects.ForeignRaw]
  -> D.Valid
  -> Result.Result wrn Error.Error ValidStuff
vrdDefHelp remainingDecls (A.A ann def) foreigns structure =
  let
    addDef validDef (ValidStuff finalForeigns struct) =
      ValidStuff finalForeigns (D.addDef (A.A ann validDef) struct)
  in
    case def of
      Source.Definition pat expr ->
        addDef
          <$> validateDef pat expr Nothing
          <*> vrdHelp remainingDecls foreigns structure

      Source.Annotation name tipe ->
        case remainingDecls of
          A.A _ (D.Def (A.A _ (Source.Definition pat expr))) : rest
           | Pattern.isVar name pat ->
              addDef
                <$> validateDef pat expr (Just tipe)
                <*> vrdHelp rest foreigns structure

          _ ->
            vrdHelp remainingDecls foreigns structure
              <* Result.throw (fst ann) (Error.TypeWithoutDefinition name)



-- VALIDATE DEFINITIONS


definitions :: [Source.Def] -> Result.Result wrn Error.Error [Valid.Def]
definitions sourceDefs =
  do  validDefs <- definitionsHelp sourceDefs

      validDefs
        |> map Valid.getPattern
        |> concatMap Pattern.boundVars
        |> detectDuplicates Error.DuplicateDefinition

      return validDefs


definitionsHelp :: [Source.Def] -> Result.Result wrn Error.Error [Valid.Def]
definitionsHelp sourceDefs =
  case sourceDefs of
    [] ->
      return []

    A.A _ (Source.Definition pat expr) : rest ->
      (:)
        <$> validateDef pat expr Nothing
        <*> definitionsHelp rest

    A.A region (Source.Annotation name tipe) : rest ->
      case rest of
        A.A _ (Source.Definition pat expr) : rest'
          | Pattern.isVar name pat ->
              (:)
                <$> validateDef pat expr (Just tipe)
                <*> definitionsHelp rest'

        _ ->
          Result.throw region (Error.TypeWithoutDefinition name)


validateDef
  :: Pattern.Raw
  -> Source.Expr
  -> Maybe Type.Raw
  -> Result.Result wrn Error.Error Valid.Def
validateDef pat expr maybeType =
  do  validExpr <- expression expr
      validateDefPattern pat validExpr
      return $ Valid.Def pat validExpr maybeType


validateDefPattern :: Pattern.Raw -> Valid.Expr -> Result.Result wrn Error.Error ()
validateDefPattern pattern body =
  case fst (Expr.collectLambdas body) of
    [] ->
        return ()

    args ->
        case pattern of
          A.A _ (Pattern.Var _) ->
              return ()

          _ ->
              let
                (A.A start _) = pattern
                (A.A end _) = last args
              in
                Result.throw (R.merge start end) (Error.BadFunctionName (length args))



-- VALIDATE EXPRESSIONS


expression :: Source.Expr -> Result.Result wrn Error.Error Valid.Expr
expression (A.A ann sourceExpression) =
  A.A ann <$>
  case sourceExpression of
    Var x ->
        return (Var x)

    Lambda pattern body ->
        Lambda
            <$> validatePattern pattern
            <*> expression body

    Binop op leftExpr rightExpr ->
        Binop op
          <$> expression leftExpr
          <*> expression rightExpr

    Case e branches ->
        Case
          <$> expression e
          <*> T.traverse (\(p,b) -> (,) <$> validatePattern p <*> expression b) branches

    Data name args ->
        Data name <$> T.traverse expression args

    Literal lit ->
        return (Literal lit)

    Range lowExpr highExpr ->
        Range
          <$> expression lowExpr
          <*> expression highExpr

    ExplicitList expressions ->
        ExplicitList
          <$> T.traverse expression expressions

    App funcExpr argExpr ->
        App
          <$> expression funcExpr
          <*> expression argExpr

    If branches finally ->
        If
          <$> T.traverse both branches
          <*> expression finally

    Access record field ->
        Access
          <$> expression record
          <*> return field

    Update record fields ->
        Update
          <$> expression record
          <*> T.traverse second fields

    Record fields ->
        let
          checkDups seenFields (field,_) =
              if Set.member field seenFields then
                  Result.throw ann (Error.DuplicateFieldName field)

              else
                  return (Set.insert field seenFields)
        in
          do  _ <- foldM checkDups Set.empty fields
              Record <$> T.traverse second fields

    Let defs body ->
        Let
          <$> definitions defs
          <*> expression body

    Cmd moduleName ->
        return (Cmd moduleName)

    Sub moduleName ->
        return (Sub moduleName)

    ForeignCmd name tipe ->
        return (ForeignCmd name tipe)

    ForeignSub name tipe ->
        return (ForeignSub name tipe)

    SaveEnv moduleName effects ->
        return (SaveEnv moduleName effects)

    GLShader uid src gltipe ->
        return (GLShader uid src gltipe)


second :: (a, Source.Expr) -> Result.Result wrn Error.Error (a, Valid.Expr)
second (value, expr) =
    (,) value <$> expression expr


both
  :: (Source.Expr, Source.Expr)
  -> Result.Result wrn Error.Error (Valid.Expr, Valid.Expr)
both (expr1, expr2) =
    (,) <$> expression expr1 <*> expression expr2



-- VALIDATE PATTERNS


validatePattern :: Pattern.Raw -> Result.Result wrn Error.Error Pattern.Raw
validatePattern pattern =
  do  detectDuplicates Error.BadPattern (Pattern.boundVars pattern)
      return pattern



-- DETECT DUPLICATES


checkDuplicates :: ValidStuff -> Result.Result wrn Error.Error ()
checkDuplicates (ValidStuff foreigns (D.Decls defs unions aliases _)) =
  let
    -- SIMPLE NAMES

    defValues =
      concatMap (Pattern.boundVars . Valid.getPattern . A.drop) defs

    foreignValues =
      map fromForeign foreigns

    fromForeign (A.A (region, _) (Effects.ForeignRaw name _)) =
      A.A region name

    -- TYPE NAMES

    (types, typeValues) =
      unzip (map fromUnion unions ++ map fromAlias aliases)

    fromUnion (A.A (region, _) (D.Type name _ ctors)) =
      ( A.A region name
      , map (A.A region . fst) ctors
      )

    fromAlias (A.A (region, _) (D.Type name _ (A.A _ tipe))) =
      (,) (A.A region name) $
        case tipe of
          Type.RRecord _ _ ->
            [A.A region name]

          _ ->
            []
  in
    F.sequenceA_
      [ detectDuplicates Error.DuplicateValueDeclaration (foreignValues ++ defValues)
      , detectDuplicates Error.DuplicateValueDeclaration (concat typeValues)
      , detectDuplicates Error.DuplicateTypeDeclaration types
      ]


detectDuplicates
    :: (String -> Error.Error)
    -> [A.Located String]
    -> Result.Result wrn Error.Error ()
detectDuplicates tag names =
  let
    add (A.A region name) dict =
      Map.insertWith (++) name [region] dict

    makeGroups pairs =
      Map.toList (foldr add Map.empty pairs)

    check (name, regions) =
      case regions of
        _ : region : _ ->
            Result.throw region (tag name)

        _ ->
            return ()
  in
    F.traverse_ check (makeGroups names)



-- UNBOUND TYPE VARIABLES


checkTypeVarsInUnion
  :: A.Commented (D.Union Type.Raw)
  -> Result.Result wrn Error.Error ()
checkTypeVarsInUnion (A.A (region,_) (D.Type name boundVars ctors)) =
  case diff boundVars (concatMap freeVars (concatMap snd ctors)) of
    (_, []) ->
        return ()

    (_, unbound) ->
        Result.throw region
          (Error.UnboundTypeVarsInUnion name boundVars unbound)


checkTypeVarsInAlias
  :: A.Commented (D.Alias Type.Raw)
  -> Result.Result wrn Error.Error ()
checkTypeVarsInAlias (A.A (region,_) (D.Type name boundVars tipe)) =
  case diff boundVars (freeVars tipe) of
    ([], []) ->
        return ()

    ([], unbound) ->
        Result.throw region
          (Error.UnboundTypeVarsInAlias name boundVars unbound)

    (unused, []) ->
        Result.throw region
          (Error.UnusedTypeVarsInAlias name boundVars unused)

    (unused, unbound) ->
        Result.throw region
          (Error.MessyTypeVarsInAlias name boundVars unused unbound)


diff :: [String] -> [A.Located String] -> ([String], [String])
diff left right =
  let
    leftSet =
      Set.fromList left

    rightSet =
      Set.fromList (map A.drop right)
  in
    ( Set.toList (Set.difference leftSet rightSet)
    , Set.toList (Set.difference rightSet leftSet)
    )


freeVars :: Type.Raw -> [A.Located String]
freeVars (A.A region tipe) =
  case tipe of
    Type.RLambda t1 t2 ->
      freeVars t1 ++ freeVars t2

    Type.RVar x ->
      [A.A region x]

    Type.RType _ ->
      []

    Type.RApp t ts ->
      concatMap freeVars (t:ts)

    Type.RRecord fields ext ->
      maybe [] freeVars ext
      ++ concatMap (freeVars . snd) fields
