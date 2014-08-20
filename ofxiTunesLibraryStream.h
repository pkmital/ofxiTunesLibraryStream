//  Library for streaming 32-bit float data by Parag K. Mital
//  http://pkmital.com

#pragma once

#include "ofxiTunesLibraryStreamViewController.h"
#include "ofxiPhone.h"

class ofxiTunesLibraryStream : public ofThread {
    
public:
    ofxiTunesLibraryStream()
    {
        bPickedSong = bPrepared = false;
    }
    ~ofxiTunesLibraryStream()
    {
        [library release];
    }
    
    void allocate(int sampleRate, int frameSize, int channels)
    {
        library = [[ofxiTunesLibraryStreamViewController alloc] init];
        [library setSampleRate:sampleRate];
        [library setChannels:channels];
        [ofxiPhoneGetGLParentView() addSubview:[library view]];
        [[library view] setHidden:YES];
        
        bPickedSong = bPrepared = false;
        
        bufferSize = frameSize * channels;
    }
    
    void pickSong()
    {
        [library setBSelectedSong:NO];
        [library setBCanceled:NO];
        [library setBConvertedSong:NO];
        [library setBConverting:NO];
        
        bPrepared = false;
        [library chooseSongTapped:nil];
        bPickedSong = true;
    }
    
    //--------------------------------------------------------------
    virtual void threadedFunction()
    {
        if(isSelected())
            [library convertTapped:nil];
    }
    
    bool isConverting()
    {
        return [library bConverting];
    }
    
    bool didFinishConverting()
    {
        return [library bConvertedSong];
    }
    
    bool isSelected()
    {
        return [library bSelectedSong];
    }
    
    bool isPrepared()
    {
        return bPrepared;
    }
    
    bool didCancel()
    {
        return [library bCanceled];
    }
    
    void setStreaming()
    {
        if(isSelected() && !bPrepared)
        {
            if([library prepareAsset] == 0)
                bPrepared = true;
            else
                cout << "Could not prepare asset!" << endl;
        }
    }
    
    bool getNextBuffer(float *samples)
    {
        if(bPrepared)
        {
            size_t totalSamplesRead = 0;
            size_t thisSamplesRead[1] = {-1};
            while(totalSamplesRead < bufferSize && thisSamplesRead[0] != 0)
            {
                if([library copyNextSampleBufferRepresentation:(samples + totalSamplesRead) withBufferSize:(bufferSize - totalSamplesRead) andSamplesRead:thisSamplesRead] == kEDLibraryAssetReader_NoMoreSampleBuffers)
                {
                    bPrepared = false;
                    return false;
                }
                totalSamplesRead += thisSamplesRead[0];
            }
            return true;
        }
        else
            return false;
    }
    
private:
    
    ofxiTunesLibraryStreamViewController *library;
    int bufferSize;
    bool bPickedSong, bPrepared;
    
};