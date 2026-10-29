param StorageAccountName string

resource StorageAccountName_resource 'Microsoft.Storage/storageAccounts@2026-04-01' = {
  name: StorageAccountName
  location: 'westeurope'
  tags: {
    CostCenter: '02-1585'
    ApplicationOwner: 'ruud.vanlieshout@dllgroup.com'
    GroupAssgnInvalid: 'false'
    AppAssgnInvalid: 'true'
    BusinessDomain: 'IT Enterprise Platforms'
    UserAssgnInvalid: 'false'
    TagVendor: 'DMAP'
    ENV: 'DEV'
    CI: 'DMAP'
    LineofIT: 'Enterprise Technology Services'
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    isLocalUserEnabled: false
    isSftpEnabled: false
    azureFilesIdentityBasedAuthentication: {
      directoryServiceOptions: 'None'
    }
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    largeFileSharesState: 'Disabled'
    isHnsEnabled: true
    networkAcls: {
      ipv6Rules: []
      resourceAccessRules: [
        {
          tenantId: '07751f8b-9617-49d5-9024-85f034f400ec'
          resourceId: '/subscriptions/c47bfe3d-881a-4142-bf65-ec835858a67b/providers/Microsoft.Security/datascanners/StorageDataScanner'
        }
      ]
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: [
        {
          value: '185.221.249.174'
          action: 'Allow'
        }
        {
          value: '62.207.93.78'
          action: 'Allow'
        }
        {
          value: '185.60.28.2'
          action: 'Allow'
        }
      ]
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
    accessTier: 'Hot'
  }
}

resource StorageAccountName_default 'Microsoft.Storage/storageAccounts/blobServices@2026-04-01' = {
  parent: StorageAccountName_resource
  name: 'default'
  properties: {
    staticWebsite: {
      enabled: false
    }
    lastAccessTimeTrackingPolicy: {
      enable: true
      name: 'AccessTimeTracking'
      trackingGranularityInDays: 1
      blobType: [
        'blockBlob'
      ]
    }
    containerDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: true
      days: 7
    }
  }
}

resource Microsoft_Storage_storageAccounts_fileServices_StorageAccountName_default 'Microsoft.Storage/storageAccounts/fileServices@2026-04-01' = {
  parent: StorageAccountName_resource
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {}
    }
    cors: {
      corsRules: []
    }
  }
}

resource Microsoft_Storage_storageAccounts_inventoryPolicies_StorageAccountName_default 'Microsoft.Storage/storageAccounts/inventoryPolicies@2026-04-01' = {
  parent: StorageAccountName_resource
  name: 'default'
  properties: {
    policy: {
      enabled: true
      type: 'Inventory'
      rules: [
        {
          destination: 'logging'
          enabled: true
          name: 'Curated all blobs'
          definition: {
            format: 'Parquet'
            schedule: 'Weekly'
            objectType: 'Blob'
            schemaFields: [
              'Name'
              'Creation-Time'
              'Last-Modified'
              'ETag'
              'Content-Length'
              'Content-Type'
              'Content-Encoding'
              'BlobType'
              'AccessTier'
              'AccessTierChangeTime'
              'AccessTierInferred'
              'Expiry-Time'
              'hdi_isfolder'
              'Owner'
              'Group'
              'Permissions'
              'Acl'
              'Metadata'
              'LastAccessTime'
            ]
            filters: {
              blobTypes: [
                'blockBlob'
                'appendBlob'
              ]
              prefixMatch: [
                'curated/'
              ]
            }
          }
        }
        {
          destination: 'logging'
          enabled: true
          name: 'Raw all blobs'
          definition: {
            format: 'Parquet'
            schedule: 'Weekly'
            objectType: 'Blob'
            schemaFields: [
              'Name'
              'Creation-Time'
              'Last-Modified'
              'ETag'
              'Content-Length'
              'Content-Type'
              'Content-Encoding'
              'BlobType'
              'AccessTier'
              'AccessTierChangeTime'
              'AccessTierInferred'
              'Expiry-Time'
              'hdi_isfolder'
              'Owner'
              'Group'
              'Permissions'
              'Acl'
              'Metadata'
              'LastAccessTime'
            ]
            filters: {
              blobTypes: [
                'blockBlob'
                'appendBlob'
              ]
              prefixMatch: [
                'raw/'
              ]
            }
          }
        }
      ]
    }
  }

  dependsOn: [
    StorageAccountName_default_logging
  ]
}

resource Microsoft_Storage_storageAccounts_queueServices_StorageAccountName_default 'Microsoft.Storage/storageAccounts/queueServices@2026-04-01' = {
  parent: StorageAccountName_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource Microsoft_Storage_storageAccounts_tableServices_StorageAccountName_default 'Microsoft.Storage/storageAccounts/tableServices@2026-04-01' = {
  parent: StorageAccountName_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource StorageAccountName_default_archive 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = {
  parent: StorageAccountName_default
  name: 'archive'
  properties: {
    // immutableStorageWithVersioning: {
    //   enabled: false
    // }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource StorageAccountName_default_curated 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = {
  parent: StorageAccountName_default
  name: 'curated'
  properties: {
    // immutableStorageWithVersioning: {
    //   enabled: false
    // }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource StorageAccountName_default_logging 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = {
  parent: StorageAccountName_default
  name: 'logging'
  properties: {
    // immutableStorageWithVersioning: {
    // //   enabled: false
    // }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource StorageAccountName_default_raw 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = {
  parent: StorageAccountName_default
  name: 'raw'
  properties: {
    // immutableStorageWithVersioning: {
    //   enabled: false
    // }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource StorageAccountName_default_test 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = {
  parent: StorageAccountName_default
  name: 'test'
  properties: {
    // immutableStorageWithVersioning: {
    //   enabled: false
    // }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource StorageAccountName_default_uctest 'Microsoft.Storage/storageAccounts/blobServices/containers@2026-04-01' = {
  parent: StorageAccountName_default
  name: 'uctest'
  properties: {
    // immutableStorageWithVersioning: {
    //   enabled: false
    // }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource StorageAccountName_default_aclactionqueue 'Microsoft.Storage/storageAccounts/queueServices/queues@2026-04-01' = {
  parent: Microsoft_Storage_storageAccounts_queueServices_StorageAccountName_default
  name: 'aclactionqueue'
  properties: {
    metadata: {}
  }
}

output resolvedStorageAccountName string = StorageAccountName_resource.name
