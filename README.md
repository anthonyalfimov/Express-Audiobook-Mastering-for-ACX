# Express Audiobook Mastering for ACX

Bash script that utilises [SoX](http://sox.sourceforge.net) to batch process audiobooks for [ACX Audio Submission](https://www.acx.com), [Author's Republic](https://www.authorsrepublic.com), [Findaway Voices](https://findawayvoices.com), etc.

The script ensures that the audio files satisfy the following requirenments:

- Peak values no higher than -3dB.
- RMS level between -23dB and -18dB.
- 44.1kHz sample rate.
- Mono channel configuration.
- 0.5 - 1.0 seconds of room tone at the beginning of the file.
- 1.0 - 5.0 seconds of room tone at the end of the file.


**Note:** The script accepts and outputs `*.wav` files. Conversion to  192kbps CBR MP3 must be handled separately.

