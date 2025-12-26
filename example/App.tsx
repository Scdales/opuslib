import { useState } from 'react';
import Opuslib from 'opuslib';
import { Button, SafeAreaView, ScrollView, Text, View, StyleSheet, Platform, PermissionsAndroid } from 'react-native';

export default function App() {
  const [isRecording, setIsRecording] = useState(false);
  const [packetCount, setPacketCount] = useState(0);
  const [totalBytes, setTotalBytes] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const startRecording = async () => {
    try {
      setError(null);
      setPacketCount(0);
      setTotalBytes(0);

      // Request microphone permission on Android
      if (Platform.OS === 'android') {
        const granted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.RECORD_AUDIO,
          {
            title: 'Microphone Permission',
            message: 'This app needs access to your microphone to record audio.',
            buttonNeutral: 'Ask Me Later',
            buttonNegative: 'Cancel',
            buttonPositive: 'OK',
          }
        );
        if (granted !== PermissionsAndroid.RESULTS.GRANTED) {
          setError('Microphone permission denied');
          return;
        }
      }

      // Subscribe to audio chunks
      const subscription = Opuslib.addListener('audioChunk', (event) => {
        setPacketCount((prev) => prev + 1);
        setTotalBytes((prev) => prev + event.data.byteLength);
        console.log(`Received Opus packet #${packetCount}: ${event.data.byteLength} bytes`);
      });

      // Start streaming with DRED enabled
      await Opuslib.startStreaming({
        sampleRate: 16000,
        channels: 1,
        bitrate: 24000,
        frameSize: 20,
        packetDuration: 100,
        dredDuration: 100, // Enable 100ms DRED recovery
      });

      setIsRecording(true);
      console.log('Recording started with Opus 1.6 support');
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      console.error('Failed to start recording:', err);
    }
  };

  const stopRecording = async () => {
    try {
      await Opuslib.stopStreaming();
      setIsRecording(false);
      console.log(`Recording stopped. Total: ${packetCount} packets, ${totalBytes} bytes`);
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
      console.error('Failed to stop recording:', err);
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.scrollView}>
        <Text style={styles.header}>Opus 1.6 with DRED</Text>
        <Text style={styles.subtitle}>iOS Native Audio Encoding Example</Text>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Configuration</Text>
          <InfoRow label="Sample Rate" value="16 kHz" />
          <InfoRow label="Bitrate" value="24 kbps" />
          <InfoRow label="Channels" value="Mono" />
          <InfoRow label="Frame Size" value="20 ms" />
          <InfoRow label="Packet Duration" value="100 ms" />
          <InfoRow label="DRED Recovery" value="100 ms" />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Controls</Text>
          <Button
            title={isRecording ? 'Stop Recording' : 'Start Recording'}
            onPress={isRecording ? stopRecording : startRecording}
            color={isRecording ? '#ff3b30' : '#007aff'}
          />
        </View>

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Statistics</Text>
          <InfoRow label="Status" value={isRecording ? 'Recording' : 'Stopped'} />
          <InfoRow label="Packets Received" value={packetCount.toString()} />
          <InfoRow label="Total Bytes" value={`${totalBytes.toLocaleString()} bytes`} />
          {totalBytes > 0 && (
            <InfoRow
              label="Avg Packet Size"
              value={`${Math.round(totalBytes / packetCount)} bytes`}
            />
          )}
        </View>

        {error && (
          <View style={[styles.section, styles.errorSection]}>
            <Text style={styles.sectionTitle}>Error</Text>
            <Text style={styles.errorText}>{error}</Text>
          </View>
        )}

        <View style={styles.section}>
          <Text style={styles.sectionTitle}>About DRED</Text>
          <Text style={styles.infoText}>
            Deep Redundancy (DRED) is an Opus 1.6 feature that embeds packet loss recovery data
            in padding. This example encodes live audio with 100ms of DRED recovery, allowing
            the decoder to reconstruct lost packets for improved quality on lossy networks.
          </Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

function InfoRow({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.infoRow}>
      <Text style={styles.infoLabel}>{label}:</Text>
      <Text style={styles.infoValue}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f5f5f5',
  },
  scrollView: {
    flex: 1,
  },
  header: {
    fontSize: 28,
    fontWeight: 'bold',
    textAlign: 'center',
    marginTop: 20,
    marginBottom: 5,
  },
  subtitle: {
    fontSize: 16,
    textAlign: 'center',
    color: '#666',
    marginBottom: 20,
  },
  section: {
    margin: 15,
    backgroundColor: '#fff',
    borderRadius: 10,
    padding: 15,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  errorSection: {
    backgroundColor: '#fff5f5',
    borderColor: '#ff3b30',
    borderWidth: 1,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 10,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
    borderBottomWidth: 1,
    borderBottomColor: '#f0f0f0',
  },
  infoLabel: {
    fontSize: 14,
    color: '#666',
  },
  infoValue: {
    fontSize: 14,
    fontWeight: '500',
  },
  errorText: {
    color: '#ff3b30',
    fontSize: 14,
  },
  infoText: {
    fontSize: 14,
    lineHeight: 20,
    color: '#666',
  },
});
