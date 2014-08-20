//
//  ofxiTunesLibraryStreamViewController.m
//  ofxiTunesLibraryStream
//

#import "ofxiTunesLibraryStreamViewController.h"
#import <AudioToolbox/AudioToolbox.h> // for the core audio constants
#import <Accelerate/Accelerate.h>

#define EXPORT_NAME @"exported.caf"

@implementation ofxiTunesLibraryStreamViewController

@synthesize songLabel;
@synthesize artistLabel;
@synthesize sizeLabel;
@synthesize coverArtView;
@synthesize conversionProgress;
@synthesize exportPath;
@synthesize bSelectedSong;
@synthesize bConvertedSong;
@synthesize bConverting;
@synthesize bCanceled;
@synthesize sampleRate;
@synthesize channels;

#pragma mark init/dealloc

- (id)init {
    if( self = [super init])
    {
        sampleRate = 44100;
        channels = 2;
    
        return self;
    }
    else
    {
        return nil;
    }
}

- (void)dealloc {
    [super dealloc];
}

#pragma mark vc lifecycle

-(void) viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
}

#pragma mark event handlers
-(IBAction) chooseSongTapped: (id) sender {
    printf("Presenting Media Picker\n");
	MPMediaPickerController *pickerController =	[[MPMediaPickerController alloc]
												 initWithMediaTypes: MPMediaTypeMusic];
	pickerController.prompt = @"Choose song to export";
	pickerController.allowsPickingMultipleItems = NO;
	pickerController.delegate = self;
	bCanceled = false;
    currentReadHead = 0;
    currentReadSize = 0;
	[self presentModalViewController:pickerController animated:YES];
	[pickerController release];
}


- (EDLibraryAssetReaderStatus)prepareAsset {
    // Get the AVURLAsset
    // set up an AVAssetReader to read from the iPod Library
	NSURL *assetURL = [song valueForProperty:MPMediaItemPropertyAssetURL];
	AVURLAsset *uasset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    
    // Check for DRM protected content
    if (uasset.hasProtectedContent) {
        return kEDLibraryAssetReader_TrackIsDRMProtected;
    }
    
    if ([uasset tracks] == 0) {
        NSLog(@"no asset tracks found");
        return kEDLibraryAssetReader_StatusFailed;
    }
    
    // Initialize a reader with a track output
    NSError *err = noErr;
    m_reader = [[AVAssetReader alloc] initWithAsset:uasset error:&err];
    if (!m_reader || err) {
        NSLog(@"could not create asset reader (%i)\n", [err code]);
        return AVAssetReaderStatusFailed;
    }
    
    // Check tracks for valid format. Currently we only support all MP3 and AAC types, WAV and AIFF is too large to handle
    for (AVAssetTrack *track in uasset.tracks) {
        NSArray *formats = track.formatDescriptions;
        for (int i=0; i<[formats count]; i++) {
            CMFormatDescriptionRef format = (CMFormatDescriptionRef)[formats objectAtIndex:i];
            
            // Check the format types
            CMMediaType mediaType = CMFormatDescriptionGetMediaType(format);
            FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(format);
            
            //NSLog(@"mediaType: %s, mediaSubType: %s", COFcc(mediaType), COFcc(mediaSubType));
            if (mediaType == kCMMediaType_Audio) {
                if (mediaSubType == kEDSupportedMediaTypeAAC ||
                    mediaSubType == kEDSupportedMediaTypeMP3) {
                    m_track = [track retain];
                    m_format = CFRetain(format);
                    break;
                }
                else{
                    NSLog(@"Selected unsupported media type");
                }
            }
            else{
                NSLog(@"Selected unsupported media type");
            }
        }
        if (m_track != nil && m_format != NULL) {
            break;
        }
    }
    
    if (m_track == nil || m_format == NULL) {
        return kEDLibraryAssetReader_UnsupportedFormat;
    }
    
    AudioChannelLayout channelLayout;
	memset(&channelLayout, 0, sizeof(AudioChannelLayout));
	channelLayout.mChannelLayoutTag = channels == 2 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono;
    
    NSDictionary *outputSettings =
    [NSDictionary dictionaryWithObjectsAndKeys:
     [NSNumber numberWithInt:kAudioFormatLinearPCM],    AVFormatIDKey,
     [NSNumber numberWithFloat:sampleRate],                AVSampleRateKey,
     [NSNumber numberWithInt:channels],                        AVNumberOfChannelsKey,
     [NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)],
     AVChannelLayoutKey,
     [NSNumber numberWithInt:16],                       AVLinearPCMBitDepthKey,
     [NSNumber numberWithBool:NO],                      AVLinearPCMIsNonInterleaved,
     [NSNumber numberWithBool:NO],                      AVLinearPCMIsFloatKey,
     [NSNumber numberWithBool:NO],                      AVLinearPCMIsBigEndianKey,
     nil];
    
    // Create an output for the found track
    m_output = [[AVAssetReaderTrackOutput alloc] initWithTrack:m_track outputSettings:outputSettings];
    [m_reader addOutput:m_output];
    
    // Start reading
    if (![m_reader startReading]) {
        NSLog(@"could not start reading asset");
        return kEDLibraryAssetReader_CouldNotStartReading;
    }
    
    return 0;
}

- (EDLibraryAssetReaderStatus)copyNextSampleBufferRepresentation:(float *)repOut withBufferSize:(size_t)bufferSize andSamplesRead:(size_t *)samplesRead{
    
    OSStatus err = noErr;
    
    if(currentReadHead == 0)
    {
        AVAssetReaderStatus status = m_reader.status;
        
        if (status != AVAssetReaderStatusReading) {
            [m_reader release];
            [m_output release];
            return kEDLibraryAssetReader_NoMoreSampleBuffers;
        }
        
        // Read the next sample buffer
        CMSampleBufferRef sampleBuffer = [m_output copyNextSampleBuffer];
        if (sampleBuffer == NULL) {
            [m_reader release];
            [m_output release];
            return kEDLibraryAssetReader_NoMoreSampleBuffers;
        }
        
        CMItemCount numSamples = CMSampleBufferGetNumSamples(sampleBuffer);
        CMBlockBufferRef audioBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
        size_t lengthAtOffset;
        size_t totalLength;
        char *samples;
        CMBlockBufferGetDataPointer(audioBuffer, 0, &lengthAtOffset, &totalLength, &samples);
        
        CMAudioFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        const AudioStreamBasicDescription *desc = CMAudioFormatDescriptionGetStreamBasicDescription(format);
        currentReadSize = numSamples * desc->mChannelsPerFrame;
//        NSLog(@"Read %ld samples", currentReadSize);
        
        assert(desc->mFormatID == kAudioFormatLinearPCM);
        assert(currentReadSize <= 32768);
        
        if (desc->mBitsPerChannel == 16) {
            vDSP_vflt16((short *)samples, 1, convertedSamples, 1, currentReadSize);
            static float divFactor=32767.0;
            vDSP_vsdiv(convertedSamples, 1, &divFactor, convertedSamples, 1, currentReadSize);
        } else {
            NSLog(@"Read %ld samples in unknown format", totalLength);
        }
        
        CFRelease(sampleBuffer);
    }
    
    if(currentReadHead + bufferSize >= currentReadSize)
    {
        memcpy(repOut, convertedSamples + currentReadHead, sizeof(float)*(currentReadSize - currentReadHead));
        currentReadHead += (currentReadSize - currentReadHead);
        *samplesRead = (currentReadSize - currentReadHead);
    }
    else
    {
        memcpy(repOut, convertedSamples + currentReadHead, sizeof(float)*bufferSize);
        currentReadHead += bufferSize;
        *samplesRead = bufferSize;
    }
    
    if(currentReadHead == currentReadSize)
        currentReadHead = 0;
    
    //NSLog(@"read: %ld", currentReadHead);
    
    return err;
}

-(IBAction) convertTapped: (id) sender {
	if (bConverting) {
		return;
	}
	bConverting = true;
	// set up an AVAssetReader to read from the iPod Library
	NSURL *assetURL = [song valueForProperty:MPMediaItemPropertyAssetURL];
	AVURLAsset *songAsset = [AVURLAsset URLAssetWithURL:assetURL options:nil];

	NSError *assetError = nil;
	AVAssetReader *assetReader = [[AVAssetReader assetReaderWithAsset:songAsset
															   error:&assetError]
								  retain];
	if (assetError) {
		NSLog (@"error: %@", assetError);
		return;
	}
	
	AVAssetReaderOutput *assetReaderOutput = [[AVAssetReaderAudioMixOutput 
											  assetReaderAudioMixOutputWithAudioTracks:songAsset.tracks
																		audioSettings: nil]
											  retain];
	if (! [assetReader canAddOutput: assetReaderOutput]) {
		NSLog (@"can't add reader output... die!");
		return;
	}
	[assetReader addOutput: assetReaderOutput];
	
	NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectoryPath = [dirs objectAtIndex:0];
	exportPath = [[documentsDirectoryPath stringByAppendingPathComponent:EXPORT_NAME] retain];
	if ([[NSFileManager defaultManager] fileExistsAtPath:exportPath]) {
		[[NSFileManager defaultManager] removeItemAtPath:exportPath error:nil];
	}
	NSURL *exportURL = [NSURL fileURLWithPath:exportPath];
	AVAssetWriter *assetWriter = [[AVAssetWriter assetWriterWithURL:exportURL
														  fileType:AVFileTypeCoreAudioFormat
															 error:&assetError]
								  retain];
	if (assetError) {
		NSLog (@"error: %@", assetError);
		return;
	}
	AudioChannelLayout channelLayout;
	memset(&channelLayout, 0, sizeof(AudioChannelLayout));
	channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
	NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
									[NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey, 
									[NSNumber numberWithFloat:44100.0], AVSampleRateKey,
									[NSNumber numberWithInt:2], AVNumberOfChannelsKey,
									[NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)], AVChannelLayoutKey,
									[NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
									[NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved,
									[NSNumber numberWithBool:NO],AVLinearPCMIsFloatKey,
									[NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
									nil];
	AVAssetWriterInput *assetWriterInput = [[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
																			  outputSettings:outputSettings]
											retain];
	if ([assetWriter canAddInput:assetWriterInput]) {
		[assetWriter addInput:assetWriterInput];
	} else {
		NSLog (@"can't add asset writer input... die!");
		return;
	}
	
	assetWriterInput.expectsMediaDataInRealTime = NO;

	[assetWriter startWriting];
	[assetReader startReading];

	AVAssetTrack *soundTrack = [songAsset.tracks objectAtIndex:0];
	CMTime startTime = CMTimeMake (0, soundTrack.naturalTimeScale);
	[assetWriter startSessionAtSourceTime: startTime];
	
	__block UInt64 convertedByteCount = 0;
	
	dispatch_queue_t mediaInputQueue = dispatch_queue_create("mediaInputQueue", NULL);
	[assetWriterInput requestMediaDataWhenReadyOnQueue:mediaInputQueue 
											usingBlock: ^ 
	 {
		 // NSLog (@"top of block");
		 while (assetWriterInput.readyForMoreMediaData) {
			CMSampleBufferRef nextBuffer = [assetReaderOutput copyNextSampleBuffer];
			if (nextBuffer) {
				// append buffer
				[assetWriterInput appendSampleBuffer: nextBuffer];
				//				NSLog (@"appended a buffer (%d bytes)", 
				//					   CMSampleBufferGetTotalSampleSize (nextBuffer));
				convertedByteCount += CMSampleBufferGetTotalSampleSize (nextBuffer);
				// oops, no
				// sizeLabel.text = [NSString stringWithFormat: @"%ld bytes converted", convertedByteCount];
				
				NSNumber *convertedByteCountNumber = [NSNumber numberWithLong:convertedByteCount];
				[self performSelectorOnMainThread:@selector(updateSizeLabel:)
									   withObject:convertedByteCountNumber
									waitUntilDone:NO];
			} else {
				// done!
				[assetWriterInput markAsFinished];
				[assetWriter finishWriting];
				[assetReader cancelReading];
				NSDictionary *outputFileAttributes = [[NSFileManager defaultManager]
													  attributesOfItemAtPath:exportPath
													  error:nil];
				NSLog (@"done. file size is %ld",
					    [outputFileAttributes fileSize]);
				NSNumber *doneFileSize = [NSNumber numberWithLong:[outputFileAttributes fileSize]];
				[self performSelectorOnMainThread:@selector(updateCompletedSizeLabel:)
									   withObject:doneFileSize
									waitUntilDone:NO];
				// release a lot of stuff
				[assetReader release];
				[assetReaderOutput release];
				[assetWriter release];
				[assetWriterInput release];
//				[exportPath release];
				
				bConvertedSong = true;
				bSelectedSong = false;
				break;
			}
			CFRelease(nextBuffer);
		}

	 }];
	NSLog (@"bottom of convertTapped:");
	bConverting = false;
}

-(void) updateSizeLabel: (NSNumber*) convertedByteCountNumber {
	UInt64 convertedByteCount = [convertedByteCountNumber longValue];
	sizeLabel.text = [NSString stringWithFormat: @"%ld bytes converted", convertedByteCount];
}

-(void) updateCompletedSizeLabel: (NSNumber*) convertedByteCountNumber {
	UInt64 convertedByteCount = [convertedByteCountNumber longValue];
	sizeLabel.text = [NSString stringWithFormat: @"done. file size is %ld", convertedByteCount];
}


#pragma mark MPMediaPickerControllerDelegate
- (void)mediaPicker: (MPMediaPickerController *)mediaPicker
  didPickMediaItems:(MPMediaItemCollection *)mediaItemCollection {
	[self dismissModalViewControllerAnimated:YES];
	if ([mediaItemCollection count] < 1) {
		return;
	}
	[song release];
	song = [[[mediaItemCollection items] objectAtIndex:0] retain];
	songLabel.hidden = NO;
	artistLabel.hidden = NO;
	coverArtView.hidden = NO;
	songLabel.text = [song valueForProperty:MPMediaItemPropertyTitle];
	artistLabel.text = [song valueForProperty:MPMediaItemPropertyArtist];
	coverArtView.image = [[song valueForProperty:MPMediaItemPropertyArtwork]
						  imageWithSize: coverArtView.bounds.size];
    
	bSelectedSong = true;
}

- (void)mediaPickerDidCancel:(MPMediaPickerController *)mediaPicker {
	[self dismissModalViewControllerAnimated:YES];
	bCanceled = true;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskPortrait;
}

@end
