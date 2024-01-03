module NammaDSL.DSL.Syntax.Storage where

import Kernel.Prelude
import NammaDSL.GeneratorCore

data TableDef = TableDef
  { tableNameHaskell :: String,
    tableNameSql :: String,
    fields :: [FieldDef],
    imports :: [String],
    queries :: [QueryDef],
    primaryKey :: [String],
    secondaryKey :: [String],
    types :: Maybe [TypeObject],
    containsEncryptedField :: Bool,
    relationalTableNamesHaskell :: [String]
  }
  deriving (Show)

newtype TypeObject = TypeObject (String, ([(String, String)], Maybe String))
  deriving (Show)

data QueryDef = QueryDef
  { queryName :: String,
    kvFunction :: String,
    params :: [((String, String), Bool)],
    whereClause :: WhereClause,
    takeFullObjectAsInput :: Bool
  }
  deriving (Show)

data WhereClause = EmptyWhere | Leaf (String, String, Maybe Operator) | Query (Operator, [WhereClause]) deriving (Show)

data Operator = And | Or | In | Eq | GreaterThan | LessThan | GreaterThanOrEq | LessThanOrEq deriving (Show, Eq)

comparisonOperator :: [Operator]
comparisonOperator = [In, Eq, GreaterThan, LessThan, GreaterThanOrEq, LessThanOrEq]

data FieldDef = FieldDef
  { fieldName :: String,
    haskellType :: String,
    beamFields :: [BeamField],
    fromTType :: Maybe String,
    isEncrypted :: Bool,
    relation :: Maybe FieldRelation,
    relationalTableNameHaskell :: Maybe String
  }
  deriving (Show)

data FieldRelation = OneToOne | MaybeOneToOne | OneToMany deriving (Show, Eq)

data FieldConstraint = PrimaryKey | SecondaryKey | NotNull | AUTOINCREMENT deriving (Show, Eq)

data BeamField = BeamField
  { bFieldName :: String,
    hFieldType :: String,
    bFieldType :: String,
    bConstraints :: [FieldConstraint],
    bSqlType :: String,
    bDefaultVal :: Maybe String,
    bfieldExtractor :: [String],
    bToTType :: Maybe String,
    bIsEncrypted :: Bool
  }
  deriving (Show)

type StorageM = BuilderM TableDef
