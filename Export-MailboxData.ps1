# Updated Content with Proper Byte Conversion

# Previous ToBytes() calls replaced with correct parsing

function ToBytes($size) {
    # Assuming $size is of type ByteQuantifiedSize
    [int64]$bytes = $size.Value # Use the Value property to get the number of bytes
    return $bytes
}

# Example for quota
$quotaInBytes = ToBytes($quota)

# Example for size
$sizeInBytes = ToBytes($size)
