module NammaDSL.Generator.SQL.Table (generateSQL) where

import Data.List (intercalate)
import Kernel.Prelude
import NammaDSL.DSL.Syntax.Storage
import Text.Casing (quietSnake)

-- Generates SQL for creating a table and altering it to add columns
generateSQL :: TableDef -> String
generateSQL tableDef =
  createTableSQL tableDef ++ "\n" ++ alterTableSQL tableDef ++ "\n" ++ addKeySQL tableDef

-- SQL for creating an empty table
createTableSQL :: TableDef -> String
createTableSQL tableDef =
  "CREATE TABLE atlas_app." ++ tableNameSql tableDef ++ " ();\n"

-- SQL for altering the table to add each column
alterTableSQL :: TableDef -> String
alterTableSQL tableDef =
  intercalate "\n" $ map (addColumnSQL (tableNameSql tableDef)) $ filter (isNothing . relation) (fields tableDef)

-- SQL for adding a single column with constraints
addColumnSQL :: String -> FieldDef -> String
addColumnSQL tableName hfieldDef =
  intercalate "\n" $
    map
      ( \fieldDef ->
          if bIsEncrypted fieldDef
            then
              generateAlterColumnSQL (quietSnake (bFieldName fieldDef) ++ "_hash") "bytea" fieldDef
                ++ "\n"
                ++ generateAlterColumnSQL (quietSnake (bFieldName fieldDef) ++ "_encrypted") "character varying(255)" fieldDef
            else generateAlterColumnSQL (quietSnake (bFieldName fieldDef)) (bSqlType fieldDef) fieldDef
      )
      (beamFields hfieldDef)
  where
    generateAlterColumnSQL :: String -> String -> BeamField -> String
    generateAlterColumnSQL fieldName_ sqlType_ beamField =
      "ALTER TABLE atlas_app." ++ tableName ++ " ADD COLUMN " ++ fieldName_ ++ " " ++ sqlType_ ++ " "
        ++ unwords (mapMaybe constraintToSQL (bConstraints beamField))
        ++ maybe "" (" default " ++) (bDefaultVal beamField)
        ++ ";"

addKeySQL :: TableDef -> String
addKeySQL tableDef =
  let keys = map quietSnake $ primaryKey tableDef <> secondaryKey tableDef
   in "ALTER TABLE atlas_app." ++ (tableNameSql tableDef) ++ " ADD PRIMARY KEY ( "
        ++ intercalate ", " keys
        ++ ");"

-- ALTER TABLE tablename ADD PRIMARY KEY (column1, column2, ...);

-- Converts a FieldConstraint to SQL
constraintToSQL :: FieldConstraint -> Maybe String
constraintToSQL NotNull = Just "NOT NULL"
constraintToSQL _ = Nothing
