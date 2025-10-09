module volo_vault::receipt;

use sui::event::emit;

// ---------------------  Events  ---------------------//
public struct ReceiptCreated has copy, drop {
    receipt_id: address,
    vault_id: address,
}

// ---------------------  Structs  ---------------------//
public struct Receipt has key, store {
    id: UID,
    vault_id: address, // This receipt belongs to which vault
}

// ---------------------  Getters  ---------------------//
public fun receipt_id(self: &Receipt): address {
    self.id.to_address()
}

public fun vault_id(self: &Receipt): address {
    self.vault_id
}

// ------------------  Main Functions  ------------------//

public(package) fun create_receipt(vault_id: address, ctx: &mut TxContext): Receipt {
    let receipt = Receipt {
        id: object::new(ctx),
        vault_id,
    };

    emit(ReceiptCreated {
        receipt_id: receipt.id.to_address(),
        vault_id,
    });

    receipt
}