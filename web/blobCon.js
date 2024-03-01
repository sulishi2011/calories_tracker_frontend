// Place this in your web/index.html file or a separate JS file that's included in your project.
function blobUrlToArrayBuffer(blobUrl, callback) {
    console.log("Fetching Blob URL:", blobUrl);
    fetch(blobUrl)
        .then(response => response.blob())
        .then(blob => {
            console.log("Blob fetched, size:", blob.size);
            const reader = new FileReader();
            reader.onload = function() {
                console.log("Blob read successfully, ArrayBuffer size:", this.result.byteLength);
                const arrayBuffer = this.result;
                // Convert ArrayBuffer to Typed Array (Uint8Array)
                const typedArray = new Uint8Array(arrayBuffer);

                // 打印转换后的数据大小
                console.log("Converted data size before callback:", typedArray.length, "bytes");

                // Call the Dart callback with the typed array
                callback({data: typedArray, error: null});
            };
            reader.onerror = function() {
                console.error("Failed to read the blob.");
                callback({data: null, error: "Failed to read the blob."});
            };
            reader.readAsArrayBuffer(blob);
        }).catch(error => {
            console.error("Error fetching the blob URL:", error.message);
            callback({data: null, error: error.message});
        });
}

// Add this to your JavaScript code
function releaseBlobUrl(blobUrl) {
    URL.revokeObjectURL(blobUrl);
}

