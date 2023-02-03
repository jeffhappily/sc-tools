{-# LANGUAGE LambdaCase #-}
{-| Translating between cardano-api/cardano-ledger and plutus representations
-}
module Convex.PlutusLedger(
  -- * Script hashes
  transScriptHash,
  unTransScriptHash,

  -- * Key hashes
  transPubKeyHash,
  unTransPubKeyHash,

  transStakeKeyHash,
  unTransStakeKeyHash,

  -- * Asset names
  transAssetName,
  unTransAssetName,

  -- * Credentials and addresses
  transCredential,
  unTransCredential,

  transStakeAddressReference,
  unTransStakeAddressReference,

  unTransAddressInEra

) where

import qualified Cardano.Api.Shelley       as C
import           Cardano.Ledger.BaseTypes  (CertIx (..), TxIx (..))
import           Cardano.Ledger.Credential (Ptr (..))
import qualified Cardano.Ledger.Mary.Value as Mary (AssetName (..))
import           Data.ByteString.Short     (fromShort)
import qualified Plutus.V1.Ledger.Api      as PV1
import qualified PlutusTx.Prelude          as PlutusTx

transScriptHash :: C.ScriptHash -> PV1.ValidatorHash
transScriptHash h = PV1.ValidatorHash (PV1.toBuiltin (C.serialiseToRawBytes h)) -- TODO: is serialiseToRawBytes the correct thing to do here?

unTransScriptHash :: PV1.ValidatorHash -> Maybe C.ScriptHash
unTransScriptHash (PV1.ValidatorHash vh) =
  C.deserialiseFromRawBytes C.AsScriptHash $ PlutusTx.fromBuiltin vh

transAssetName :: Mary.AssetName -> PV1.TokenName
transAssetName (Mary.AssetName bs) = PV1.TokenName (PV1.toBuiltin (fromShort bs))

unTransAssetName :: PV1.TokenName -> C.AssetName
unTransAssetName (PV1.TokenName bs) = C.AssetName $ PV1.fromBuiltin bs

unTransPubKeyHash :: PV1.PubKeyHash -> Maybe (C.Hash C.PaymentKey)
unTransPubKeyHash (PV1.PubKeyHash pkh) =
  let bsx = PlutusTx.fromBuiltin pkh
  in C.deserialiseFromRawBytes (C.AsHash C.AsPaymentKey) bsx

transPubKeyHash :: C.Hash C.PaymentKey -> PV1.PubKeyHash
transPubKeyHash = PV1.PubKeyHash . PlutusTx.toBuiltin . C.serialiseToRawBytes

transStakeKeyHash :: C.Hash C.StakeKey -> PV1.PubKeyHash
transStakeKeyHash = PV1.PubKeyHash . PlutusTx.toBuiltin . C.serialiseToRawBytes

unTransStakeKeyHash :: PV1.PubKeyHash -> Maybe (C.Hash C.StakeKey)
unTransStakeKeyHash (PV1.PubKeyHash pkh) =
  let bsx = PlutusTx.fromBuiltin pkh
  in C.deserialiseFromRawBytes (C.AsHash C.AsStakeKey) bsx

unTransCredential :: PV1.Credential -> Maybe C.PaymentCredential
unTransCredential = \case
  PV1.PubKeyCredential c -> C.PaymentCredentialByKey <$> unTransPubKeyHash c
  PV1.ScriptCredential c -> C.PaymentCredentialByScript <$> unTransScriptHash c

transCredential :: C.PaymentCredential -> PV1.Credential
transCredential = \case
  C.PaymentCredentialByKey k    -> PV1.PubKeyCredential (transPubKeyHash k)
  C.PaymentCredentialByScript k -> PV1.ScriptCredential (transScriptHash k)

transStakeAddressReference :: C.StakeAddressReference -> Maybe PV1.StakingCredential
transStakeAddressReference = \case
  C.StakeAddressByValue x -> Just (PV1.StakingHash $ fromCardanoStakeCredential x)
  C.StakeAddressByPointer (C.StakeAddressPointer (Ptr (C.SlotNo slotNo) (TxIx txIx) (CertIx ptrIx))) -> Just (PV1.StakingPtr (fromIntegral slotNo) (fromIntegral txIx) (fromIntegral ptrIx))
  C.NoStakeAddress -> Nothing

fromCardanoStakeCredential :: C.StakeCredential -> PV1.Credential
fromCardanoStakeCredential (C.StakeCredentialByKey stakeKeyHash) = PV1.PubKeyCredential (transStakeKeyHash stakeKeyHash)
fromCardanoStakeCredential (C.StakeCredentialByScript scriptHash) = PV1.ScriptCredential (transScriptHash scriptHash)

toCardanoStakeCredential :: PV1.Credential -> Maybe C.StakeCredential
toCardanoStakeCredential (PV1.PubKeyCredential pubKeyHash) = C.StakeCredentialByKey <$> unTransStakeKeyHash pubKeyHash
toCardanoStakeCredential (PV1.ScriptCredential validatorHash) = C.StakeCredentialByScript <$> unTransScriptHash validatorHash

unTransStakeAddressReference :: Maybe PV1.StakingCredential -> Maybe C.StakeAddressReference
unTransStakeAddressReference Nothing = Just C.NoStakeAddress
unTransStakeAddressReference (Just (PV1.StakingHash credential)) =
  C.StakeAddressByValue <$> toCardanoStakeCredential credential
unTransStakeAddressReference (Just (PV1.StakingPtr slotNo txIx ptrIx)) =
  Just (C.StakeAddressByPointer (C.StakeAddressPointer (Ptr (C.SlotNo $ fromIntegral slotNo) (TxIx $ fromIntegral txIx) (CertIx $ fromIntegral ptrIx))))

unTransAddressInEra :: C.NetworkId -> PV1.Address -> Maybe (C.AddressInEra C.BabbageEra)
unTransAddressInEra networkId (PV1.Address cred staking) =
  C.AddressInEra (C.ShelleyAddressInEra C.ShelleyBasedEraBabbage) <$>
    (C.makeShelleyAddress networkId
      <$> unTransCredential cred
      <*> unTransStakeAddressReference staking
      )
