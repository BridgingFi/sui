import {
  addToast,
  BreadcrumbItem,
  Breadcrumbs,
  Button,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Form,
  Input,
  Popover,
  PopoverContent,
  PopoverTrigger,
  Select,
  SelectItem,
  Spinner,
  Textarea,
  Tooltip,
} from "@heroui/react";
import { Check, QrCode, WarningCircle } from "iconoir-react";
import { QRCodeSVG } from "qrcode.react";
import {
  useCurrentAccount,
  useSignTransaction,
  useSuiClient,
} from "@mysten/dapp-kit";
import { Transaction, TransactionDataBuilder } from "@mysten/sui/transactions";
import { SUI_CLOCK_OBJECT_ID } from "@mysten/sui/utils";
import { useState, useMemo, useEffect } from "react";
import { useParams, useSearchParams } from "react-router-dom";
import dayjs from "dayjs";
import { Steps } from "@ark-ui/react/steps";

import { AppLayout } from "@/components/layout/AppLayout";
import { useVaultInfo } from "@/hooks/useVaultInfo";
import { useOperatorCaps } from "@/hooks/useOperatorCaps";
import { useCoinBalance } from "@/hooks/useCoinBalance";
import { useCoinDecimals } from "@/hooks/useCoinDecimals";
import { useBridgingFiPosition } from "@/hooks/useBridgingFiPosition";
import { loggers } from "@/utils/debug";
import { extractBuildError } from "@/utils/transaction";
import {
  type ExecuteParams,
  type ParsedRepaymentData,
  RepaymentMode,
  buildRepaymentURL,
  parseRepaymentData,
} from "@/utils/repayment";
import { CopyButton } from "@/components/common/CopyButton";
import { DryrunResultView } from "@/components/repayment/DryrunResultView";
import {
  formatCoinAmount,
  truncateAddress,
  truncateCoinType,
} from "@/utils/format";

// Use latest package ID for calling contracts (may be upgraded)
const VOLO_VAULT_PACKAGE_ID_LATEST =
  import.meta.env.VITE_VOLO_VAULT_PACKAGE_ID_LATEST || "";
const VOLO_OPERATION_ID = import.meta.env.VITE_VOLO_OPERATION_ID || "";
const VOLO_ORACLE_CONFIG_ID = import.meta.env.VITE_VOLO_ORACLE_CONFIG_ID || "";
const { errorLog, debugLog } = loggers("app:routes:repayment");

/**
 * Repayment route component for BridgingFi
 * Route: /vault/:vaultId/repay
 * Supports three modes:
 * 1. operator-init: Operator initiates repayment request
 * 2. repayer: Repayer builds, simulates, and signs transaction
 * 3. operator-sign: Operator signs and executes transaction
 */
export function RepaymentRoute() {
  const currentAccount = useCurrentAccount();
  const client = useSuiClient();
  const { mutateAsync: signTransaction } = useSignTransaction();

  // Get route params and search params
  const { vaultId, assetType } = useParams<{
    vaultId: string;
    assetType: string;
  }>();
  const [searchParams] = useSearchParams();

  // Parse repayment data from search params
  const { repaymentMode, supplyCoinsParams, executeParams, parseError } =
    useMemo(() => {
      let data: ParsedRepaymentData;
      let error: string | null = null;

      try {
        data = parseRepaymentData(searchParams);
        debugLog("Parsed repayment data: %O", data);
      } catch (err) {
        data = { mode: RepaymentMode.INIT };
        error =
          err instanceof Error ? err.message : "Failed to parse repayment data";
        errorLog("Error parsing repayment data: %O", err);
      }

      return {
        repaymentMode: data.mode,
        supplyCoinsParams:
          data.mode !== RepaymentMode.INIT ? data.params : null,
        executeParams: data.mode === RepaymentMode.EXECUTE ? data.params : null,
        parseError: error,
      };
    }, [searchParams]);

  // Get vault info directly from vault_id
  const {
    freePrincipal,
    claimablePrincipal,
    coinType,
    isLoading: isLoadingVaultInfo,
  } = useVaultInfo(vaultId);

  // Get position data (must be called unconditionally for hooks)
  const { position, isLoading: isLoadingPosition } = useBridgingFiPosition(
    vaultId || null,
    coinType || null,
    assetType || null,
  );

  const coinDecimals = useCoinDecimals(coinType || "");

  // Get operator caps only for operator modes
  const isOperatorMode =
    repaymentMode === RepaymentMode.INIT ||
    repaymentMode === RepaymentMode.EXECUTE;
  const { operatorCaps } = useOperatorCaps(isOperatorMode);

  // Get coin balance only for repayer mode
  const { rawBalance, isLoading: isLoadingBalance } = useCoinBalance(
    repaymentMode === RepaymentMode.SUPPLY_COINS && coinType ? coinType : "",
  );

  // Unified amount state for all modes
  const [amount, setAmount] = useState("");
  const [selectedOperatorCapId, setSelectedOperatorCapId] = useState<
    string | null
  >(null);

  // State for repayer mode
  const [dryrunResult, setDryrunResult] = useState<any>(null);
  const [signedTxData, setSignedTxData] = useState<ExecuteParams | null>(null);
  // State for execution result (operator mode)
  const [executeResult, setExecuteResult] = useState<{
    digest: string;
    result: any;
  } | null>(null);

  // QR Code Popover state
  const [qrCodeUrl, setQrCodeUrl] = useState<string | null>(null);
  const [requestUrl, setRequestUrl] = useState("");

  // State for all modes
  const [isSimulating, setIsSimulating] = useState(false);
  const [isSigning, setIsSigning] = useState(false);
  // Store built transaction and hash for signing step
  const [builtTxData, setBuiltTxData] = useState<{
    tx: Transaction;
    coinIds: string;
    txHash: string;
  } | null>(null);

  // Initialize amount from request or position
  useEffect(() => {
    if (supplyCoinsParams?.amount) {
      setAmount(supplyCoinsParams.amount);
    } else if (position && coinDecimals !== null) {
      const defaultAmount = formatCoinAmount(
        position.currentDebt,
        coinDecimals,
      );

      if (defaultAmount) {
        setAmount(defaultAmount);
      }
    }
  }, [supplyCoinsParams, position, coinDecimals]);

  // Initialize selected operator cap
  useEffect(() => {
    if (
      repaymentMode === RepaymentMode.INIT &&
      operatorCaps &&
      operatorCaps.length > 0
    ) {
      const firstCap = operatorCaps[0];

      if (firstCap) {
        setSelectedOperatorCapId(firstCap.objectId);
      }
    }
  }, [repaymentMode, operatorCaps]);

  // Update request URL when dependencies change
  useEffect(() => {
    if (
      amount &&
      selectedOperatorCapId &&
      currentAccount &&
      assetType &&
      vaultId
    ) {
      const url = buildRepaymentURL(
        {
          operatorCapId: selectedOperatorCapId,
          operatorAddress: currentAccount.address,
          amount: amount,
        },
        vaultId,
        assetType!,
      );

      setRequestUrl(url);
    } else {
      setRequestUrl("");
    }
  }, [amount, selectedOperatorCapId, currentAccount, assetType, vaultId]);

  // Build repayment transaction
  const buildRepaymentTransaction = async (
    amount: string,
    operatorCapId: string,
    operatorAddress: string,
    coinIds?: string, // Optional: exact coin IDs for precise reconstruction
    repayerAddress?: string, // Optional: fallback to get coins if coinOps not provided
  ): Promise<{ tx: Transaction; coinIds: string }> => {
    const amountValue = parseFloat(amount);
    const amountInCoinUnits = BigInt(
      Math.floor(amountValue * Math.pow(10, coinDecimals!)),
    );

    const tx = new Transaction();

    // Set sender to operator address (operator pays gas)
    tx.setSender(operatorAddress);

    // Step 0: Get and prepare repayer's coin
    let coinIdsArray: string[] = [];

    if (coinIds) {
      coinIdsArray = coinIds.split(",").filter((id) => id.length > 0);
    } else if (repayerAddress) {
      const allCoins = await client.getCoins({
        owner: repayerAddress,
        coinType,
      });

      // Gather enough coins to cover the amount
      let collected = 0n;

      for (const coin of allCoins.data) {
        if (coin.coinObjectId && coin.balance) {
          coinIdsArray.push(coin.coinObjectId);
          collected += BigInt(coin.balance);
          if (collected >= amountInCoinUnits) {
            break;
          }
        }
      }

      if (collected < amountInCoinUnits) {
        throw new Error(
          `Repayer does not have enough ${coinType} to cover repayment amount`,
        );
      }
    } else {
      throw new Error(
        "Either coinOps or repayerAddress must be provided to build transaction",
      );
    }

    // Split the required amount from repayer's coin. Merge coins first if there
    // are multiple coins.
    const coinInput = tx.object(coinIdsArray[0]!);
    const coin = tx.splitCoins(
      coinIdsArray.length === 1
        ? coinInput
        : tx.mergeCoins(
            coinInput,
            coinIdsArray.slice(1).map((id) => tx.object(id)),
          ),
      [amountInCoinUnits],
    );

    // Step 1: update_free_principal_value
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::vault::update_free_principal_value`,
      typeArguments: [coinType!],
      arguments: [
        tx.object(vaultId!),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.object(SUI_CLOCK_OBJECT_ID),
      ],
    });

    // Step 2: update_value (BridgingFi position)
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::update_value`,
      typeArguments: [coinType!],
      arguments: [
        tx.object(vaultId!),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.object(SUI_CLOCK_OBJECT_ID),
        tx.pure.string(assetType!),
      ],
    });

    // Step 3: Get TypeName for BridgingFiPosition
    const bridgingfiTypeName = tx.moveCall({
      target: `0x1::type_name::get`,
      typeArguments: [
        `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::BridgingFiPosition`,
      ],
      arguments: [],
    });

    // Step 4: Create vector<TypeName> for defi_asset_types
    const defiAssetTypes = tx.moveCall({
      target: `0x1::vector::singleton`,
      typeArguments: [`0x1::type_name::TypeName`],
      arguments: [bridgingfiTypeName],
    });

    // Extract index from assetType (e.g., "BridgingFiPosition0" -> 0)
    const match = assetType!.match(/(\d+)$/);
    const defiAssetId = match && match[1] ? parseInt(match[1], 10) : 0;

    // Step 5: start_op_with_bag
    const [bag, txBag, txBagForCheckValueUpdate, balanceT, balanceCoinType] =
      tx.moveCall({
        target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::start_op_with_bag`,
        typeArguments: [coinType!, coinType!, coinType!],
        arguments: [
          tx.object(vaultId!),
          tx.object(VOLO_OPERATION_ID),
          tx.object(operatorCapId), // Use operator's OperatorCap ID
          tx.object(SUI_CLOCK_OBJECT_ID),
          tx.pure.vector("u8", [defiAssetId]),
          defiAssetTypes,
          tx.pure.u64(0), // No investment, just repayment
          tx.pure.u64(0),
        ],
      }) as unknown as [
        { $kind: "NestedResult"; NestedResult: [number, number] },
        { $kind: "NestedResult"; NestedResult: [number, number] },
        { $kind: "NestedResult"; NestedResult: [number, number] },
        { $kind: "NestedResult"; NestedResult: [number, number] },
        { $kind: "NestedResult"; NestedResult: [number, number] },
      ];

    // Step 6: Remove BridgingFiPosition from bag
    const positionObj = tx.moveCall({
      target: `0x2::bag::remove`,
      typeArguments: [
        `0x1::ascii::String`,
        `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::BridgingFiPosition`,
      ],
      arguments: [bag, tx.pure.string(assetType!)],
    });

    // Step 7: repay (coin is already split in Step 0)
    const remainingCoin = tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::repay`,
      typeArguments: [coinType!],
      arguments: [
        tx.object(vaultId!),
        positionObj,
        coin,
        tx.pure.u64(amountInCoinUnits),
        tx.object(SUI_CLOCK_OBJECT_ID),
      ],
    });

    // Transfer any remaining coin back to repayer if there's change
    tx.transferObjects([remainingCoin], tx.pure.address(repayerAddress!));

    // Step 9: Add position back to bag
    tx.moveCall({
      target: `0x2::bag::add`,
      typeArguments: [
        `0x1::ascii::String`,
        `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::BridgingFiPosition`,
      ],
      arguments: [bag, tx.pure.string(assetType!), positionObj],
    });

    // Step 10: end_op_with_bag
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::end_op_with_bag`,
      typeArguments: [coinType!, coinType!, coinType!],
      arguments: [
        tx.object(vaultId!),
        tx.object(VOLO_OPERATION_ID),
        tx.object(operatorCapId),
        bag,
        txBag,
        balanceT,
        balanceCoinType,
      ],
    });

    // Step 11: update_free_principal_value
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::vault::update_free_principal_value`,
      typeArguments: [coinType!],
      arguments: [
        tx.object(vaultId!),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.object(SUI_CLOCK_OBJECT_ID),
      ],
    });

    // Step 12: update_value (BridgingFi position)
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::bridgingfi_adapter::update_value`,
      typeArguments: [coinType!],
      arguments: [
        tx.object(vaultId!),
        tx.object(VOLO_ORACLE_CONFIG_ID),
        tx.object(SUI_CLOCK_OBJECT_ID),
        tx.pure.string(assetType!),
      ],
    });

    // Step 13: end_op_value_update_with_bag
    tx.moveCall({
      target: `${VOLO_VAULT_PACKAGE_ID_LATEST}::operation::end_op_value_update_with_bag`,
      typeArguments: [coinType!, coinType!],
      arguments: [
        tx.object(vaultId!),
        tx.object(VOLO_OPERATION_ID),
        tx.object(operatorCapId),
        tx.object(SUI_CLOCK_OBJECT_ID),
        txBagForCheckValueUpdate,
      ],
    });

    return { tx, coinIds: coinIdsArray.join(",") };
  };

  // Handle repayer: Build and simulate transaction
  const handleSimulate = async () => {
    setIsSimulating(true);
    setSignedTxData(null);
    setBuiltTxData(null);
    setDryrunResult(null);

    try {
      // Build transaction (sender is operator, coin is from repayer)
      const { tx, coinIds } = await buildRepaymentTransaction(
        amount,
        supplyCoinsParams!.operatorCapId,
        supplyCoinsParams!.operatorAddress, // operator address (sender, from request)
        executeParams?.coinIds, // coinOps: will be recorded after building
        currentAccount!.address, // repayer address (fallback)
      );

      // Build transaction bytes
      const txBytes = await tx.build({ client }).catch(extractBuildError);
      // Get transaction hash
      const txHash = TransactionDataBuilder.getDigestFromBytes(txBytes);

      // Simulate transaction
      const dryrun = await client.dryRunTransactionBlock({
        transactionBlock: txBytes,
      });

      debugLog("dryrun result: %o", dryrun);

      // Store transaction and hash for signing step
      setBuiltTxData({ tx, coinIds, txHash });
      setDryrunResult(dryrun);
    } catch (err) {
      addToast({
        title: "Simulation failed",
        description: err instanceof Error ? err.message : "Unknown error",
        color: "danger",
      });
      errorLog("Simulation failed", err);
    } finally {
      setIsSimulating(false);
    }
  };

  // Handle repayer: Sign transaction
  const handleSign = async () => {
    setIsSigning(true);

    try {
      if (!builtTxData) {
        throw new Error("Transaction not built. Please simulate first.");
      }

      // Sign transaction using useSignTransaction hook
      // Note: repayer signs the transaction even though sender is operator
      // This is because repayer provides the coin
      const signResult = await signTransaction({
        transaction: builtTxData.tx,
      });

      if (!signResult || !signResult.signature) {
        throw new Error("Transaction signing was cancelled or failed");
      }

      // Create signed transaction data
      const signedTx: ExecuteParams = {
        ...supplyCoinsParams!,
        amount: amount, // Use repayer's amount (may differ from operator's initial amount)
        txHash: builtTxData.txHash,
        signature: signResult.signature,
        coinIds: builtTxData.coinIds,
      };

      setSignedTxData(signedTx);
      setRequestUrl(buildRepaymentURL(signedTx, vaultId!, assetType!));
    } catch (err) {
      addToast({
        title: "Signing failed",
        description: err instanceof Error ? err.message : "Unknown error",
        color: "danger",
      });
      errorLog("Repayer sign error: %O", err);
    } finally {
      setIsSigning(false);
    }
  };

  // Handle operator-sign: Rebuild, verify, sign and execute
  const handleOperatorSignAndExecute = async () => {
    setIsSigning(true);
    try {
      if (!builtTxData) {
        throw new Error("Transaction not built. Please simulate first.");
      }

      // Verify hash consistency
      if (builtTxData.txHash !== executeParams!.txHash) {
        throw new Error(
          "Transaction hash mismatch. Parameters may have changed.",
        );
      }

      // Sign transaction using useSignTransaction hook
      // Note: repayer signs the transaction even though sender is operator
      // This is because repayer provides the coin
      const signResult = await signTransaction({
        transaction: builtTxData.tx,
      });

      if (!signResult || !signResult.signature) {
        throw new Error("Transaction signing was cancelled or failed");
      }

      // Merge signatures - signatures is an array
      const signatures =
        signResult.signature == executeParams!.signature
          ? [signResult.signature]
          : [
              executeParams!.signature, // Repayer's signature
              signResult.signature, // Operator's signature
            ];

      // Execute transaction
      const result = await client.executeTransactionBlock({
        transactionBlock: signResult.bytes, // Use bytes from signTransaction
        signature: signatures,
        options: {
          showBalanceChanges: true,
          showEvents: true,
          showEffects: true,
          showObjectChanges: true,
        },
      });

      // Store execution result for display
      // Convert executeResult to dryrunResult format for DryrunResultView
      const dryrunFormat = {
        effects: result.effects,
        balanceChanges: result.balanceChanges,
        objectChanges: result.objectChanges,
        events: result.events,
      };

      setExecuteResult({
        digest: result.digest,
        result: dryrunFormat,
      });

      // Show success toast
      addToast({
        title: "Transaction executed successfully",
        description: `Transaction digest: ${result.digest}`,
        color: "success",
      });
    } catch (err) {
      addToast({
        title: "Execution failed",
        description: err instanceof Error ? err.message : "Unknown error",
        color: "danger",
      });
      errorLog("Execution failed", err);
    } finally {
      setIsSigning(false);
    }
  };

  // Validate amount input
  const validateAmount = (value: string): string | null => {
    if (!value) return "Please enter an amount";

    const amountValue = parseFloat(value);

    if (isNaN(amountValue) || amountValue <= 0) {
      return "Please enter a valid amount";
    }

    if (repaymentMode === RepaymentMode.SUPPLY_COINS) {
      // Validate coin balance
      const amountInCoinUnits = BigInt(
        Math.floor(amountValue * Math.pow(10, coinDecimals!)),
      );
      const userBalance = BigInt(rawBalance || "0");

      if (amountInCoinUnits > userBalance) {
        return "Insufficient coin balance";
      }
    }

    return null;
  };

  // Show loading state if fetching data
  if (isLoadingPosition || isLoadingVaultInfo || coinDecimals === null) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center py-8">
          <Spinner size="lg" />
        </div>
      </AppLayout>
    );
  }

  if (!vaultId || !assetType || !coinType || !position || parseError) {
    return (
      <AppLayout>
        <div className="container mx-auto py-8">
          <div className="space-y-2">
            {parseError && <p>{parseError}</p>}
            {!vaultId && <p>Vault not found</p>}
            {!assetType && <p>Asset type not specified</p>}
            {!coinType && <p>Coin type not specified</p>}
            {!position && <p>Position not found</p>}
          </div>
        </div>
      </AppLayout>
    );
  }

  return (
    <AppLayout>
      <header className="space-y-2">
        <Breadcrumbs>
          <BreadcrumbItem href="/">Vaults</BreadcrumbItem>
          <BreadcrumbItem>
            <div className="flex items-center">
              <Tooltip
                showArrow
                color="foreground"
                content={vaultId}
                delay={200}
              >
                <span>{truncateAddress(vaultId)}</span>
              </Tooltip>
              <CopyButton value={vaultId} />
            </div>
          </BreadcrumbItem>
        </Breadcrumbs>

        <h1 className="text-3xl font-semibold">
          {coinType.split("::").pop()} Vault
        </h1>

        <div className="flex flex-wrap items-center gap-4 text-sm text-default-500">
          <div className="flex items-center">
            <Tooltip
              showArrow
              color="foreground"
              content={coinType}
              delay={200}
            >
              <span>Coin Type: {truncateCoinType(coinType)}</span>
            </Tooltip>
            <CopyButton value={coinType} />
          </div>
          <span>
            Free Principal:{" "}
            <span className="font-mono text-foreground">
              {formatCoinAmount(freePrincipal, coinDecimals)}
            </span>
          </span>
          <span>
            Claimable Principal:{" "}
            <span className="font-mono text-foreground">
              {formatCoinAmount(claimablePrincipal, coinDecimals)}
            </span>
          </span>
        </div>

        <Divider />

        {/* Position Debt Information */}
        <div className="text-sm text-default-500">
          <h2 className="flex items-baseline gap-2 text-lg">
            Position Information
            <div className="flex items-center gap-1 text-sm">
              APR:
              <span className="text-foreground">{position.aprPercentage}</span>
            </div>
          </h2>

          <div className="flex items-baseline gap-2">
            Asset Type:
            <div className="flex flex-1 items-start">
              <code className="font-mono text-xs break-all text-foreground">
                {assetType}
              </code>
              <CopyButton value={assetType} />
            </div>
          </div>
          <div className="flex items-baseline gap-2">
            Custodian Account:
            <div className="flex flex-1 items-start">
              <code className="font-mono text-xs break-all text-foreground">
                {position.custodianAccount}
              </code>
              <CopyButton value={position.custodianAccount} />
            </div>
          </div>
          <div className="flex items-baseline gap-2">
            Outstanding Balance:
            <div className="flex flex-1 items-baseline gap-2">
              {coinDecimals === null ? (
                <div className="flex items-center gap-2">
                  <WarningCircle className="h-4 w-4 text-danger" />
                  <span className="text-danger">
                    Coin decimals not available
                  </span>
                </div>
              ) : (
                <p className="font-mono text-foreground">
                  {formatCoinAmount(position.outstandingBalance, coinDecimals)}
                </p>
              )}
              <p className="text-xs">
                Last Updated: {position.lastUpdateDate} (UTC)
              </p>
            </div>
          </div>
          <div className="flex items-baseline gap-2">
            Current Debt (Estimated):
            <div className="flex flex-1 items-baseline gap-2">
              {coinDecimals === null ? (
                <div className="flex items-center gap-2">
                  <WarningCircle className="h-4 w-4 text-danger" />
                  <span className="text-danger">
                    Coin decimals not available
                  </span>
                </div>
              ) : (
                <div className="flex items-center">
                  <span className="font-mono text-foreground">
                    {formatCoinAmount(position.currentDebt, coinDecimals)}
                  </span>
                  <CopyButton
                    value={
                      formatCoinAmount(position.currentDebt, coinDecimals) || ""
                    }
                  />
                </div>
              )}
              {position.currentDebtCalculatedAt && (
                <p className="text-xs">
                  Estimated at:{" "}
                  {dayjs
                    .utc(position.currentDebtCalculatedAt)
                    .format("YYYY-MM-DD HH:mm:ss")}{" "}
                  (UTC)
                </p>
              )}
            </div>
          </div>
        </div>
      </header>

      <Divider />

      {/* Steps Indicator */}
      <Card>
        <CardBody className="items-center">
          <Steps.Root
            className="w-full max-w-3xl"
            count={3}
            step={repaymentMode}
          >
            <Steps.List className="flex items-center justify-between">
              {[
                "Operator Initiates Request",
                "Repayer Supplies Coins",
                "Operator Executes",
              ].map((step, index) => (
                <Steps.Item
                  key={index}
                  className="relative flex items-center not-last:flex-1"
                  index={index}
                >
                  <Steps.Trigger className="group flex items-center gap-3 rounded-md text-left">
                    <Steps.Indicator className="relative flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-sm font-semibold data-complete:bg-primary data-complete:text-primary-foreground data-current:bg-primary data-current:text-primary-foreground data-incomplete:bg-default data-incomplete:text-default-foreground">
                      <span className="group-data-complete:hidden group-data-current:block">
                        {index + 1}
                      </span>
                      <Check className="hidden h-4 w-4 group-data-complete:block" />
                    </Steps.Indicator>
                    <span className="text-sm font-medium text-foreground">
                      {step}
                    </span>
                  </Steps.Trigger>

                  <Steps.Separator
                    className="mx-3 h-0.5 flex-1 bg-default data-complete:bg-primary"
                    hidden={index === 2}
                  />
                </Steps.Item>
              ))}
            </Steps.List>

            {/* Step Content */}
            <div className="mt-8 rounded-lg bg-default-100 p-4 text-default-500">
              <Steps.Item index={0}>
                <Steps.Content index={0}>
                  <h3 className="mb-2 font-semibold text-foreground">
                    Initiates Request with Operator Cap and Amount
                  </h3>
                  <ul className="list-inside list-disc text-sm">
                    <li>Enter the repayment amount</li>
                    <li>Select an operator capability (OperatorCap)</li>
                    <li>Share the URL or QR code with the repayer</li>
                  </ul>
                </Steps.Content>
              </Steps.Item>

              <Steps.Item index={1}>
                <Steps.Content index={1}>
                  <h3 className="mb-2 font-semibold text-foreground">
                    Supplies Coins, Signs Transaction and Returns to Operator
                  </h3>
                  <ul className="list-inside list-disc text-sm">
                    <li>Review the repayment request details</li>
                    <li>Ensure you have sufficient coin balance</li>
                    <li>Build and simulate the transaction</li>
                    <li>Sign the transaction with your wallet</li>
                    <li>Share the signed transaction with the operator</li>
                  </ul>
                </Steps.Content>
              </Steps.Item>

              <Steps.Item index={2}>
                <Steps.Content index={2}>
                  <h3 className="mb-2 font-semibold text-foreground">
                    Signs and Executes Transaction
                  </h3>
                  <ul className="list-inside list-disc text-sm">
                    <li>Review the signed transaction from the repayer</li>
                    <li>Verify the transaction details are correct</li>
                    <li>Add your signature to complete the multi-signature</li>
                    <li>Execute the transaction on-chain</li>
                  </ul>
                </Steps.Content>
              </Steps.Item>
            </div>
          </Steps.Root>
        </CardBody>
      </Card>

      <Divider />

      {/* Repayment Request */}
      <Card>
        <CardHeader>
          {repaymentMode === RepaymentMode.INIT
            ? "Initiate Repayment Request"
            : repaymentMode === RepaymentMode.SUPPLY_COINS
              ? "Repay to Vault"
              : "Sign & Execute Repayment"}
        </CardHeader>
        <CardBody
          as={Form}
          className="space-y-4"
          onSubmit={(e) => {
            e.preventDefault();
            switch (repaymentMode) {
              case RepaymentMode.SUPPLY_COINS:
                !dryrunResult ? handleSimulate() : handleSign();
                break;
              case RepaymentMode.EXECUTE:
                !dryrunResult
                  ? handleSimulate()
                  : handleOperatorSignAndExecute();
                break;
            }
          }}
        >
          {/* Amount Input - Always shown first */}
          <Input
            description={
              <div className="flex items-center gap-1">
                <span>
                  Current Debt:{" "}
                  {formatCoinAmount(position.currentDebt, coinDecimals)}
                </span>
                {repaymentMode === RepaymentMode.SUPPLY_COINS && (
                  <span>
                    Balance in wallet:{" "}
                    {formatCoinAmount(rawBalance, coinDecimals)}
                  </span>
                )}
              </div>
            }
            isReadOnly={repaymentMode === RepaymentMode.EXECUTE}
            label="Repayment Amount"
            placeholder="0.000000"
            step={1 / Math.pow(10, coinDecimals)}
            type="number"
            validate={validateAmount}
            value={amount}
            onChange={(e) => {
              setDryrunResult(null);
              setAmount(e.target.value);
            }}
          />

          {/* Operator Cap Selection (operator-init only) */}
          {repaymentMode === RepaymentMode.INIT && (
            <Select
              label="Operator Cap"
              selectedKeys={
                selectedOperatorCapId ? [selectedOperatorCapId] : undefined
              }
              onSelectionChange={(keys) => {
                setSelectedOperatorCapId(
                  (Array.from(keys)[0] as string) || null,
                );
              }}
            >
              {operatorCaps?.map((cap) => (
                <SelectItem key={cap.objectId}>{cap.objectId}</SelectItem>
              ))}
            </Select>
          )}

          {supplyCoinsParams && (
            <>
              <Card className="w-full border border-default-200">
                <CardBody>
                  <div className="text-xs text-default-500">
                    Operator Cap ID
                  </div>
                  <div className="font-mono text-sm break-all">
                    {supplyCoinsParams.operatorCapId}
                  </div>
                  <div className="mt-2 text-xs text-default-500">
                    Operator Address
                  </div>
                  <div className="font-mono text-sm break-all">
                    {supplyCoinsParams.operatorAddress}
                  </div>
                </CardBody>
              </Card>

              {/* Simulation Result (repayer only) */}
              {dryrunResult && (
                <div className="w-full space-y-4">
                  <div className="flex items-center justify-between">
                    <h3 className="text-lg font-semibold">Simulation Result</h3>
                    <Button
                      color="primary"
                      isLoading={isSimulating}
                      size="sm"
                      onPress={handleSimulate}
                    >
                      Re-simulate
                    </Button>
                  </div>

                  <DryrunResultView
                    coinDecimals={coinDecimals}
                    dryrunResult={dryrunResult}
                  />
                </div>
              )}

              {builtTxData && (
                <Card className="w-full border border-default-200">
                  <CardHeader>Simulated Transaction</CardHeader>
                  <CardBody className="text-sm">
                    <div className="text-xs text-default-500">
                      Transaction Hash
                    </div>
                    <code className="font-mono text-sm break-all">
                      {builtTxData.txHash}
                    </code>
                  </CardBody>
                </Card>
              )}
            </>
          )}

          {/* Signed Transaction Info (operator-sign) */}
          {executeParams && (
            <Card className="w-full border border-default-200">
              <CardHeader>Signed Transaction</CardHeader>
              <CardBody>
                <div className="text-xs text-default-500">Transaction Hash</div>
                <code className="font-mono text-sm break-all">
                  {executeParams.txHash}
                </code>
                <div className="mt-2 text-xs text-default-500">Signature</div>
                <code className="font-mono text-sm break-all">
                  {executeParams.signature}
                </code>
              </CardBody>
            </Card>
          )}

          {/* Execution Result (operator-sign after execution) */}
          {executeResult && (
            <div className="w-full space-y-4">
              <div className="flex items-center justify-between">
                <h3 className="text-lg font-semibold">Execution Result</h3>
                <div className="flex items-center gap-2">
                  <span className="text-sm text-default-500">
                    Digest: {executeResult.digest}
                  </span>
                  <CopyButton value={executeResult.digest} />
                </div>
              </div>
              <DryrunResultView
                coinDecimals={coinDecimals}
                dryrunResult={executeResult.result}
              />
            </div>
          )}

          {/* Request URL (operator-init) */}
          {(repaymentMode === RepaymentMode.INIT || requestUrl) && (
            <Textarea
              isReadOnly
              description="Share this URL or QR code with the repayer to supply coins."
              endContent={
                <div className="flex items-center gap-2">
                  <CopyButton value={requestUrl} />
                  <Popover
                    showArrow
                    color="foreground"
                    placement="top-end"
                    onOpenChange={(isOpen) => {
                      if (isOpen && requestUrl) {
                        setQrCodeUrl(requestUrl);
                      }
                    }}
                  >
                    <PopoverTrigger>
                      <Button
                        isIconOnly
                        aria-label="Generate QR code"
                        isDisabled={!requestUrl}
                        size="sm"
                        variant="light"
                      >
                        <QrCode className="h-4 w-4" />
                      </Button>
                    </PopoverTrigger>
                    <PopoverContent className="p-4">
                      {qrCodeUrl && <QRCodeSVG size={256} value={qrCodeUrl} />}
                    </PopoverContent>
                  </Popover>
                </div>
              }
              label="Repayment Request URL"
              minRows={2}
              value={requestUrl}
            />
          )}

          {/* Action Buttons */}
          <div className="flex gap-2">
            {repaymentMode === RepaymentMode.SUPPLY_COINS && !signedTxData && (
              <Button
                color="primary"
                isLoading={isSimulating || isSigning}
                type="submit"
              >
                {dryrunResult ? "Sign" : "Simulate"}
              </Button>
            )}

            {repaymentMode === RepaymentMode.EXECUTE && !executeResult && (
              <Button
                color="primary"
                isLoading={isSimulating || isSigning}
                type="submit"
              >
                {dryrunResult ? "Sign & Execute" : "Simulate"}
              </Button>
            )}
          </div>
        </CardBody>
      </Card>
    </AppLayout>
  );
}
