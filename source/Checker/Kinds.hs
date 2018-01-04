-- Mainly provides a kind checker on types
{-# LANGUAGE ImplicitParams #-}

module Checker.Kinds (kindCheck
                    , inferKindOfType
                    , joinCoeffectConstr
                    , hasLub
                    , joinKind) where

import Control.Monad.State.Strict
import Control.Monad.Trans.Maybe

import Checker.Monad
import Checker.Predicates
import Checker.Primitives
import Syntax.Expr
import Syntax.Pretty
import Context
import Utils


-- Currently we expect that a type scheme has kind KType
kindCheck :: (?globals :: Globals) => Span -> TypeScheme -> MaybeT Checker ()
kindCheck s (Forall _ quantifiedVariables ty) = do
  kind <- inferKindOfType' s quantifiedVariables ty
  case kind of
    KType -> return ()
    _     -> illKindedNEq s KType kind

inferKindOfType :: (?globals :: Globals) => Span -> Type -> MaybeT Checker Kind
inferKindOfType s t = do
    checkerState <- get
    inferKindOfType' s (stripQuantifiers $ tyVarContext checkerState) t

inferKindOfType' :: (?globals :: Globals) => Span -> Ctxt Kind -> Type -> MaybeT Checker Kind
inferKindOfType' s quantifiedVariables =
    typeFoldM (TypeFold kFunOrPair kCon kBox kDiamond kVar kApp kInt kFunOrPair kInfix)
  where
    kFunOrPair KType KType = return KType
    kFunOrPair KType y = illKindedNEq s KType y
    kFunOrPair x _     = illKindedNEq s KType x

    kCon conId =
      case lookup conId typeLevelConstructors of
        Just kind -> return kind
        Nothing   -> halt $ UnboundVariableError (Just s) (pretty conId ++ " constructor.")

    kBox _ KType = return KType
    kBox _ x = illKindedNEq s KType x

    kDiamond _ KType = return KType
    kDiamond _ x     = illKindedNEq s KType x

    kVar tyVar =
      case lookup tyVar quantifiedVariables of
        Just kind -> return kind
        Nothing   -> halt $ UnboundVariableError (Just s)
                          $ pretty tyVar ++ " is unbound (not quantified)."

    kApp (KFun k1 k2) kArg | k1 `hasLub` kArg = return k2
    kApp k kArg = illKindedNEq s (KFun kArg (KPoly $ mkId "...")) k

    kInt _ = return $ KConstr "Nat="

    kInfix op k1 k2 =
      case lookup op typeLevelConstructors of
        Just (KFun k1' (KFun k2' kr)) ->
          if k1 `hasLub` k1'
            then if k2 `hasLub` k2' then return kr
            else illKindedNEq s k2' k2
          else illKindedNEq s k1' k1
        Just _ -> unhandled
        Nothing   -> halt $ UnboundVariableError (Just s) (op ++ " operator.")

joinKind :: Kind -> Kind -> Maybe Kind
joinKind k1 k2 | k1 == k2 = Just k1
joinKind (KConstr kc1) (KConstr kc2) =
  case joinCoeffectConstr kc1 kc2 of
    Nothing -> Nothing
    Just kc -> Just $ KConstr kc
joinKind _ _ = Nothing

hasLub :: Kind -> Kind -> Bool
hasLub k1 k2 =
  case joinKind k1 k2 of
    Nothing -> False
    Just _  -> True

joinCoeffectConstr :: String -> String -> Maybe String
--joinCoeffectConstr "Nat" n | "Nat" `isPrefixOf` n = Just n
--joinCoeffectConstr n "Nat" | "Nat" `isPrefixOf` n = Just n
joinCoeffectConstr "Float" "Nat" = Just "Float"
joinCoeffectConstr "Nat" "Float" = Just "Float"
joinCoeffectConstr k k' | k == k' = Just k
joinCoeffectConstr _ _ = Nothing