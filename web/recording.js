// web/recording.js
let mediaRecorder;
let audioChunks = [];

function startRecording() {

    navigator.mediaDevices.getUserMedia({ audio: true })
        .then(stream => {
            const options = { mimeType: 'audio/webm' }; // 示例格式
            console.log("Stream obtained", stream);
            mediaRecorder = new MediaRecorder(stream, options);

            // Log the MediaRecorder's configuration
            console.log("MediaRecorder mimeType:", mediaRecorder.mimeType);
            console.log("MediaRecorder state:", mediaRecorder.state);
            console.log("MediaRecorder audioBitsPerSecond:", mediaRecorder.audioBitsPerSecond);
 
            audioChunks = [];

            mediaRecorder.addEventListener("dataavailable", event => {
                console.log("Data available: chunk size", event.data.size);
                audioChunks.push(event.data);
            });

            mediaRecorder.start();

        })
        .catch(error => {
            console.error("Error obtaining media stream:", error);
        });
}

function stopRecording() {
    console.log('JavaScript: stopRecording called');
    return new Promise((resolve, reject) => {
        if (!mediaRecorder) {
            console.error("MediaRecorder not initialized");
            reject("MediaRecorder not initialized");
            return;
        }

        mediaRecorder.addEventListener("stop", () => {
            const audioBlob = new Blob(audioChunks, { type: 'audio/webm' });
            const audioUrl = URL.createObjectURL(audioBlob);
            console.log("Recording stopped, URL created:", audioUrl);
            // Clear the audioChunks array to be ready for the next recording
            audioChunks = [];
            resolve(audioUrl);
        }, { once: true }); // Ensure the event listener is added only once

        mediaRecorder.stop();
        console.log("Stop recording called");
    });
}
