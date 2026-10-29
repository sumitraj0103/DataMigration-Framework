import pandas as pd # type: ignore


def build_rbac_strategy_review(
    strategy_path,
    discovered_rbacs_path,
    output_path
):
    strategy = pd.read_csv(strategy_path)
    discovered = pd.read_parquet(discovered_rbacs_path)

    strategy_columns = strategy.columns.tolist()

    comparison_columns = [
        "principalId",
        "roleName",
        "scopeType",
        "resourceGroupName",
        "storageAccountName",
        "containerName"
    ]

    stakeholder_columns = [
        "RequiredInProd",
        "Strategy",
        "RehearsalEquivalentPrincipal",
        "ProdEquivalentPrincipal",
        "Notes"
    ]

    # Keep only the columns used by the stakeholder strategy
    discovered_review = discovered[
        [
            "principalId",
            "principalName",
            "roleName",
            "scopeType",
            "resourceGroupName",
            "storageAccountName",
            "containerName",
            "principalCategory",
            "environment"
        ]
    ].copy()

    # Add stakeholder columns
    for column in stakeholder_columns:
        discovered_review[column] = ""

    # Normalize comparison fields
    strategy_keys = strategy[
        comparison_columns
    ].fillna("").astype(str)

    discovered_keys = discovered_review[
        comparison_columns
    ].fillna("").astype(str)

    strategy_lookup = {
        key: index
        for index, key in zip(
            strategy_keys.index,
            map(tuple, strategy_keys.to_numpy())
        )
    }

    discovered_key_set = set(
        discovered_keys.apply(tuple, axis=1)
    )

    # Carry previous stakeholder decisions into current discovery
    for index, key in discovered_keys.iterrows():
        key = tuple(key)

        if key in strategy_lookup:
            strategy_index = strategy_lookup[key]

            for column in stakeholder_columns:
                discovered_review.at[index, column] = (
                    strategy.at[strategy_index, column]
                )
        else:
            discovered_review.at[index, "Strategy"] = "Review"
            discovered_review.at[index, "Notes"] = "New RBAC discovered"

    # Find RBACs that existed in strategy but are no longer discovered
    removed_rows = []

    for index, key in zip(
        strategy_keys.index,
        map(tuple, strategy_keys.to_numpy())
    ):

        if key not in discovered_key_set:
            removed_row = strategy.loc[index].copy()

            removed_row["Notes"] = "Removed"

            removed_rows.append(removed_row)

    if removed_rows:
        removed_df = pd.DataFrame(
            removed_rows,
            columns=strategy_columns
        )

        review = pd.concat(
            [discovered_review, removed_df],
            ignore_index=True
        )
    else:
        review = discovered_review

    # Preserve exact strategy column order
    review = review[strategy_columns]

    # Sort by principalName case-insensitively
    review["_sort_principal_name"] = (
        review["principalName"].fillna("").astype(str).str.lower()
    )
    review = review.sort_values(
        by=["_sort_principal_name"]
    ).drop(columns="_sort_principal_name") # type: ignore

    review.to_csv(
        output_path,
        index=False
    )

    print(
        f"RBAC strategy review created: "
        f"{len(review)} rows, "
        f"{len(removed_rows)} removed RBAC(s)"
    )

    return review

