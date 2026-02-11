// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Trust } from "intuition-contracts-v2/Trust.sol";
import { TrustToken } from "intuition-contracts-v2/legacy/TrustToken.sol";
import { MultiVault } from "intuition-contracts-v2/protocol/MultiVault.sol";
import { BondingCurveRegistry } from "intuition-contracts-v2/protocol/curves/BondingCurveRegistry.sol";
import {
    SatelliteEmissionsController
} from "intuition-contracts-v2/protocol/emissions/SatelliteEmissionsController.sol";
import { TrustBonding } from "intuition-contracts-v2/protocol/emissions/TrustBonding.sol";
import { WrappedTrust } from "intuition-contracts-v2/WrappedTrust.sol";
import { AtomWallet } from "intuition-contracts-v2/protocol/wallet/AtomWallet.sol";
import { AtomWalletFactory } from "intuition-contracts-v2/protocol/wallet/AtomWalletFactory.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

struct Protocol {
    Trust trust;
    WrappedTrust wrappedTrust;
    TrustToken trustLegacy;
    TrustBonding trustBonding;
    BondingCurveRegistry curveRegistry;
    MultiVault multiVault;
    SatelliteEmissionsController satelliteEmissionsController;
    AtomWalletFactory atomWalletFactory;
    UpgradeableBeacon atomWalletBeacon;
}

struct Users {
    address payable admin;
    address payable controller;
    address payable timelock;
    address payable alice;
    address payable bob;
    address payable charlie;
}
