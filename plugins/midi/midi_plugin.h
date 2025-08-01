//
//  midi_plugin.h
//  godot_plugin
//
//  Created by Sergey Minakov on 14.08.2020.
//  Copyright © 2020 Godot. All rights reserved.
//

#ifndef midi_plugin_h
#define midi_plugin_h

#import <Foundation/Foundation.h>
#import <CoreMIDI/CoreMIDI.h>

// Godot头文件
#include "core/object/class_db.h"
#include "core/config/engine.h"
#include "core/input/input.h"
#include "core/input/input_event.h"
#include "core/input/input_enums.h"
#include "core/os/os.h"

// MIDI消息回调函数类型定义
typedef void (*MIDIMessageCallback)(int note, int velocity, int channel, bool is_note_on);
typedef void (*MIDIDeviceChangedCallback)(void);

// C接口函数声明
#ifdef __cplusplus
extern "C" {
#endif

// 插件初始化和清理
void midi_plugin_init(void);
void midi_plugin_cleanup(void);

// 设备管理
int midi_get_connected_inputs_count(void);
const char* midi_get_input_name(int index);
void midi_refresh_devices(void);

// 设备管理（扩展接口）
int midi_get_device_count(void);
const char* midi_get_device_name(int deviceId);
int midi_get_device_type(int deviceId);
bool midi_connect_device(int deviceId);
bool midi_disconnect_device(int deviceId);
bool midi_is_device_connected(int deviceId);

// MIDI发送接口
bool midi_send_note_on(int deviceId, int channel, int note, int velocity);
bool midi_send_note_off(int deviceId, int channel, int note);
bool midi_send_control_change(int deviceId, int channel, int controller, int value);
bool midi_send_program_change(int deviceId, int channel, int program);
bool midi_send_pitch_bend(int deviceId, int channel, int value);


// 回调设置
void midi_set_message_callback(MIDIMessageCallback callback);
void midi_set_device_changed_callback(MIDIDeviceChangedCallback callback);

// 注入MIDI输入事件到Godot Input系统（用于插件内部调用）
void midi_inject_note_on(int channel, int note, int velocity);
void midi_inject_note_off(int channel, int note, int velocity);
void midi_inject_control_change(int channel, int controller, int value);
void midi_inject_program_change(int channel, int program);
void midi_inject_pitch_bend(int channel, int value);

#ifdef __cplusplus
}
#endif

// MIDIPlugin Objective-C类声明
@interface MIDIPlugin : NSObject

// MIDI 客户端和端口
@property (nonatomic, assign) MIDIClientRef midiClient;
@property (nonatomic, assign) MIDIPortRef inputPort;
@property (nonatomic, assign) MIDIPortRef outputPort;

// 设备管理
@property (nonatomic, strong) NSMutableDictionary *connectedDevices;

// 初始化方法
- (instancetype)init;
- (void)dealloc;

// 设备管理方法
- (NSArray *)getMidiDevices;
- (NSDictionary *)getDeviceInfo:(int)deviceId;
- (BOOL)connectDevice:(int)deviceId;
- (BOOL)disconnectDevice:(int)deviceId;
- (BOOL)isDeviceConnected:(int)deviceId;
- (void)reconnectAllDevices;

// MIDI发送方法
- (BOOL)sendNoteOn:(int)deviceId channel:(int)channel note:(int)note velocity:(int)velocity;
- (BOOL)sendNoteOff:(int)deviceId channel:(int)channel note:(int)note;
- (BOOL)sendControlChange:(int)deviceId channel:(int)channel controller:(int)controller value:(int)value;
- (BOOL)sendProgramChange:(int)deviceId channel:(int)channel program:(int)program;
- (BOOL)sendPitchBend:(int)deviceId channel:(int)channel value:(int)value;

// 注入MIDI输入事件到Godot Input系统（供插件自身逻辑调用）
- (void)injectNoteOnWithChannel:(int)channel note:(int)note velocity:(int)velocity;
- (void)injectNoteOffWithChannel:(int)channel note:(int)note velocity:(int)velocity;
- (void)injectControlChangeWithChannel:(int)channel controller:(int)controller value:(int)value;
- (void)injectProgramChangeWithChannel:(int)channel program:(int)program;
- (void)injectPitchBendWithChannel:(int)channel value:(int)value;

@end




// Godot插件入口函数声明
void godot_plugin_init();
void godot_plugin_deinit();

#endif /* midi_plugin_h */ 
