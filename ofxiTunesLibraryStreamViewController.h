//
//  ofxiTunesLibraryStreamViewController.h
//  part of ofxiTunesLibraryStream
//
//  Original "VTM_AViPodReader" code by Chris Adamson
//
//  Edited for streaming 32-bit float data by Parag K. Mital
//  http://pkmital.com

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <CoreMedia/CMSampleBuffer.h>

typedef enum {
    kEDSupportedMediaTypeAAC = 'aac ',
    kEDSupportedMediaTypeMP3 = '.mp3'
} EDSupportedMediaType;

typedef enum {
    kEDLibraryAssetReader_UnsupportedFormat,
    kEDLibraryAssetReader_TrackIsDRMProtected,
    kEDLibraryAssetReader_CouldNotStartReading,
    kEDLibraryAssetReader_StatusFailed,
    kEDLibraryAssetReader_Invalidated,
    kEDLibraryAssetReader_NoMoreSampleBuffers,
    kEDLibraryAssetReader_BufferCorrupted
    
} EDLibraryAssetReaderStatus;

@interface ofxiTunesLibraryStreamViewController : UIViewController <MPMediaPickerControllerDelegate>
{
    AVAssetReader       *m_reader;
    AVAssetTrack        *m_track;
    NSArray             *m_format;
    AVAssetReaderTrackOutput *m_output;
    float               convertedSamples[32768] __attribute__((aligned(16)));
    size_t              currentReadHead;
    size_t              currentReadSize;
    
    
	MPMediaItem			*song;

	NSString			*exportPath;
	UILabel				*songLabel,
						*artistLabel,
						*sizeLabel;
	UIImageView			*coverArtView;
	UIProgressView		*conversionProgress;
    
    size_t              sampleRate;
    size_t              channels;
    
	
	BOOL				bSelectedSong, bConvertedSong, bConverting, bCanceled;
}


@property (assign) BOOL bCanceled;
@property (assign) BOOL bConverting;
@property (assign) BOOL bSelectedSong;
@property (assign) BOOL bConvertedSong;
@property (assign) size_t sampleRate;
@property (assign) size_t channels;
@property (assign) NSString *exportPath;

@property (nonatomic, retain) IBOutlet UILabel *songLabel;
@property (nonatomic, retain) IBOutlet UILabel *artistLabel;
@property (nonatomic, retain) IBOutlet UILabel *sizeLabel;
@property (nonatomic, retain) IBOutlet UIImageView *coverArtView;
@property (nonatomic, retain) IBOutlet UIProgressView *conversionProgress;

-(IBAction) chooseSongTapped: (id) sender;
-(IBAction) convertTapped: (id) sender;

-(EDLibraryAssetReaderStatus) prepareAsset;
-(EDLibraryAssetReaderStatus) copyNextSampleBufferRepresentation:(float *)repOut withBufferSize:(size_t)bufferSize andSamplesRead:(size_t *)samplesRead;

// Older versions of iOS (deprecated) if supporting iOS < 5
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation;
// iOS6
- (BOOL)shouldAutorotate;
// iOS6
- (NSUInteger)supportedInterfaceOrientations;

@end

