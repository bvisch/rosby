{-# LANGUAGE LambdaCase #-}
module Rosby.Protocol.Serial where

import Control.Applicative (Alternative((<|>)))
import Data.ByteString (ByteString())
import qualified Data.ByteString as B
import qualified Data.ByteString.Char8 as B8
import Data.Attoparsec.ByteString (Parser(), (<?>))
import qualified Data.Attoparsec.ByteString as P
import Data.Foldable
import Data.Word8
import Test.QuickCheck

data Primitive
  = Str Int ByteString -- ^ Strings are indexed by their length
  | Num Integer -- ^ Numbers are integers
  | Array Int [Primitive] -- ^ Arrays are indexed by their length and can
                          -- contain Str and Int types
  deriving (Eq, Show)

isCR = (== 13)
isLF = (== 10)

lineSep :: Parser ()
lineSep = P.skip isCR >> P.skip isLF <?> "lineSep"

strParser :: Parser Primitive
strParser = do
  P.word8 _dollar
  num <- P.takeWhile isDigit
  lineSep
  case B8.readInt num of
    Just (num', _) -> do
      str <- P.take num'
      lineSep
      pure $ Str num' str
    Nothing        -> fail "String length must be an integer"
  where
    isDigit c = c >= 48 && c <= 57

intParser :: Parser Primitive
intParser = do
  P.word8 _colon
  num <- P.takeWhile isDigit
  lineSep
  case B8.readInteger num of
    Just (num', _) -> pure $ Num num'
    Nothing        -> fail "Failed to parse integer"

arrayParser :: Parser Primitive
arrayParser = do
  P.word8 _asterisk
  num <- P.takeWhile isDigit
  lineSep
  case B8.readInt num of
    Just (num', _) -> do
      prims <- P.count num' (strParser <|> intParser)
      pure $ Array num' prims
    Nothing -> fail "Array length must be integer"

primParser :: Parser Primitive
primParser = arrayParser <|> strParser <|> intParser

runParser :: ByteString -> Either String Primitive
runParser = P.eitherResult . P.parse primParser

serialize :: Primitive -> ByteString
serialize (Str len value) = "$" <> (B8.pack . show $ len) <> "\r\n" <> value <> "\r\n"
serialize (Num n) = ":" <> (B8.pack . show $ n) <> "\r\n"
serialize (Array len values) =
  "*" <> (B8.pack . show $ len) <> "\r\n" <> (serializeValues values) <> "\r\n"
  where
    serializeValues = B.concat . map serialize

instance Arbitrary Primitive where
  arbitrary = do
    size <- arbitrarySizedNatural
    oneof [ Str size . B8.pack <$> vectorOf size arbitraryASCIIChar
          , Num <$> arbitrary @Integer
          , Array size <$> vectorOf size arbitraryNumOrStr
          ]
      where
        arbitraryNumOrStr = suchThat (arbitrary @Primitive) onlyNumOrStr
        onlyNumOrStr = \case
          Str _ _ -> True
          Num _   -> True
          _       -> False
