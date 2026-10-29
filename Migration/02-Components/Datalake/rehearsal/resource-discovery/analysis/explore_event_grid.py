import pandas as pd # type: ignore

df = pd.read_parquet("outputs/discovery/event_grid_subscriptions.parquet")

trigger_counts: pd.Series = (
    df.groupby(["triggerName", "environment"]).size().sort_values(ascending=False)
)

filtered_counts = trigger_counts[trigger_counts > 1]

print(filtered_counts.head(20))

print(df["dependencyType"].value_counts(dropna=False))

for url in df["endpointBaseUrl"][:5]:
    print(url)

# print(df[["environment", "endpointBaseUrl", "resourceGroup", "triggerName", "includedEventTypes", "storageAccountName"]][df["storageAccountName"]=="mscstadmapdev03"])

# print(trigger_counts.head(20))

# trigger_name = trigger_counts.index[0]

# print(
#     df[df["triggerName"] == trigger_name][
#         [
#             "environment",
#             "sourceResourceId",
#             "systemTopicName",
#             "eventSubscriptionName",
#             "triggerName"
#         ]
#     ]

# )