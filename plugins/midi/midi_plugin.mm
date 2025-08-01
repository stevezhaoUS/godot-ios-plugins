//
//  midi_plugin.mm
//  godot_plugin
//
//  Created by Sergey Minakov on 14.08.2020.
//  Copyright © 2020 Godot. All rights reserved.
//

#import "midi_plugin.h"

// 全局 MIDIPlugin 实例
static MIDIPlugin *g_midiPlugin = nil;





// MIDI 输入回调函数
static void midi_input_callback_static(const MIDIPacketList *packet_list, void *read_proc_ref_con, void *src_conn_ref_con) {
    if (!g_midiPlugin) return;
    
    const MIDIPacket *packet = &packet_list->packet[0];
    
    for (int i = 0; i < packet_list->numPackets; i++) {
        if (packet->length < 3) {
            packet = MIDIPacketNext(packet);
            continue;
        }
        
        int status = packet->data[0];
        int data1 = packet->data[1];
        int data2 = packet->data[2];
        
        // 解析 MIDI 消息
        int channel = status & 0x0F;
        int message_type = status >> 4 & 0x0F;
        
        // 创建 Ref<InputEventMIDI> 并注入到 Godot Input 系统
        Ref<InputEventMIDI> event;
        event.instantiate();
        event->set_channel(channel);
        event->set_message((MIDIMessage)message_type);

        if (message_type < 0xA) {
            event->set_pitch(data1);
            event->set_velocity(data2);
        }

        // 注入到 Godot Input 系统
        Input::get_singleton()->parse_input_event(event);
        
        packet = MIDIPacketNext(packet);
    }
}

// MIDI 通知回调函数
static void midi_notify_callback(const MIDINotification *message, void *refCon) {
    MIDIPlugin *plugin = (__bridge MIDIPlugin *)refCon;
    
    switch (message->messageID) {
        case kMIDIMsgObjectAdded:
            NSLog(@"[MIDI DEBUG] 📱 检测到新MIDI设备连接");
            // 自动重连所有设备
            [plugin reconnectAllDevices];
            break;
        case kMIDIMsgObjectRemoved:
            NSLog(@"[MIDI DEBUG] 📱 检测到MIDI设备断开");
            // 自动重连所有设备
            [plugin reconnectAllDevices];
            break;
        default:
            break;
    }
}

// MIDIPlugin Objective-C实现
@implementation MIDIPlugin

- (instancetype)init {
    self = [super init];
    if (self) {
        NSLog(@"[MIDI DEBUG] 🎹 MIDI插件初始化开始...");
        
        // 初始化设备连接状态字典
        self.connectedDevices = [NSMutableDictionary dictionary];
        
        // 初始化 Core MIDI
        OSStatus status = MIDIClientCreate(CFSTR("Godot MIDI Plugin"), 
                                          midi_notify_callback, 
                                          (__bridge void *)self, 
                                          &_midiClient);
        if (status != noErr) {
            NSLog(@"[MIDI DEBUG] ❌ 创建MIDI客户端失败, status: %d", (int)status);
            return nil;
        }
        NSLog(@"[MIDI DEBUG] ✅ MIDI客户端创建成功");
        
        // 创建输入端口
        status = MIDIInputPortCreate(_midiClient, CFSTR("Input Port"), 
                                    midi_input_callback_static, 
                                    (__bridge void *)self, &_inputPort);
        if (status != noErr) {
            NSLog(@"[MIDI DEBUG] ❌ 创建MIDI输入端口失败, status: %d", (int)status);
            return nil;
        }
        NSLog(@"[MIDI DEBUG] ✅ MIDI输入端口创建成功");
        
        // 创建输出端口
        status = MIDIOutputPortCreate(_midiClient, CFSTR("Output Port"), &_outputPort);
        if (status != noErr) {
            NSLog(@"[MIDI DEBUG] ❌ 创建MIDI输出端口失败, status: %d", (int)status);
            return nil;
        }
        NSLog(@"[MIDI DEBUG] ✅ MIDI输出端口创建成功");
        
        // 自动连接所有MIDI输入设备
        NSLog(@"[MIDI DEBUG] 🔌 开始自动连接MIDI输入设备...");
        ItemCount source_count = MIDIGetNumberOfSources();
        int connected_count = 0;
        
        for (ItemCount i = 0; i < source_count; i++) {
            MIDIEndpointRef source = MIDIGetSource(i);
            
            // 获取设备名称用于调试
            CFStringRef name;
            OSStatus name_status = MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name);
            NSString *deviceName = @"Unknown Device";
            if (name_status == noErr) {
                deviceName = (__bridge NSString *)name;
            }
            
            // 连接到设备
            OSStatus status = MIDIPortConnectSource(_inputPort, source, (__bridge void *)self);
            if (status == noErr) {
                connected_count++;
                [self.connectedDevices setObject:@YES forKey:@(i)];
                NSLog(@"[MIDI DEBUG] ✅ 自动连接MIDI设备 %d: %@", (int)i, deviceName);
            } else {
                NSLog(@"[MIDI DEBUG] ❌ 连接MIDI设备 %d 失败, status: %d", (int)i, (int)status);
            }
        }
        
        NSLog(@"[MIDI DEBUG] 🔌 自动连接完成，成功连接 %d 个MIDI输入设备", connected_count);
        
        NSLog(@"[MIDI DEBUG] 🎹 MIDI插件初始化完成!");
    }
    return self;
}

- (void)dealloc {
    NSLog(@"[MIDI DEBUG] 🧹 MIDI插件清理中...");
    
    // 清理 Core MIDI 资源
    if (_inputPort) {
        MIDIPortDispose(_inputPort);
        _inputPort = 0;
    }
    
    if (_outputPort) {
        MIDIPortDispose(_outputPort);
        _outputPort = 0;
    }
    
    if (_midiClient) {
        MIDIClientDispose(_midiClient);
        _midiClient = 0;
    }
    
    NSLog(@"[MIDI DEBUG] ✅ MIDI插件清理完成");
}

- (NSArray *)getMidiDevices {
    NSMutableArray *devices = [NSMutableArray array];
    
    // 扫描输入设备
    NSLog(@"[MIDI DEBUG] 📥 扫描MIDI输入设备...");
    ItemCount source_count = MIDIGetNumberOfSources();
          NSLog(@"[MIDI DEBUG] 📥 找到 %d 个MIDI输入设备", (int)source_count);
    
    for (ItemCount i = 0; i < source_count; i++) {
        MIDIEndpointRef source = MIDIGetSource(i);
        
        CFStringRef name;
        OSStatus status = MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name);
        NSString *deviceName = @"Unknown Device";
        if (status == noErr) {
            deviceName = (__bridge NSString *)name;
        } else {
            NSLog(@"[MIDI DEBUG] ❌ 获取设备 %d 名称失败, status: %d", (int)i, (int)status);
        }
        
        NSDictionary *device = @{
            @"id": @(i),
            @"name": deviceName,
            @"type": @"source"
        };
        [devices addObject:device];
        
        NSLog(@"[MIDI DEBUG] 📥 输入设备 %d: %@", (int)i, deviceName);
    }
    
    // 扫描输出设备
    NSLog(@"[MIDI DEBUG] 📤 扫描MIDI输出设备...");
    ItemCount dest_count = MIDIGetNumberOfDestinations();
    NSLog(@"[MIDI DEBUG] 📤 找到 %d 个MIDI输出设备", (int)dest_count);
    
    for (ItemCount i = 0; i < dest_count; i++) {
        MIDIEndpointRef dest = MIDIGetDestination(i);
        
        CFStringRef name;
        OSStatus status = MIDIObjectGetStringProperty(dest, kMIDIPropertyName, &name);
        NSString *deviceName = @"Unknown Device";
        if (status == noErr) {
            deviceName = (__bridge NSString *)name;
        } else {
            NSLog(@"[MIDI DEBUG] ❌ 获取设备 %d 名称失败, status: %d", (int)i, (int)status);
        }
        
        NSDictionary *device = @{
            @"id": @(i + source_count),
            @"name": deviceName,
            @"type": @"destination"
        };
        [devices addObject:device];
        
        NSLog(@"[MIDI DEBUG] 📤 输出设备 %d: %@", (int)i, deviceName);
    }
    
    NSLog(@"[MIDI DEBUG] ✅ 设备扫描完成，总共找到 %d 个设备", (int)[devices count]);
    return devices;
}

- (NSDictionary *)getDeviceInfo:(int)deviceId {
    NSArray *devices = [self getMidiDevices];
    if (deviceId >= 0 && deviceId < [devices count]) {
        return devices[deviceId];
    }
    return nil;
}

- (BOOL)connectDevice:(int)deviceId {
    NSArray *devices = [self getMidiDevices];
    if (deviceId >= 0 && deviceId < [devices count]) {
        NSDictionary *device = devices[deviceId];
        NSString *type = device[@"type"];
        
        if ([type isEqualToString:@"source"]) {
            MIDIEndpointRef source = MIDIGetSource(deviceId);
            OSStatus status = MIDIPortConnectSource(_inputPort, source, (__bridge void *)self);
            if (status == noErr) {
                [self.connectedDevices setObject:@YES forKey:@(deviceId)];
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)disconnectDevice:(int)deviceId {
    NSArray *devices = [self getMidiDevices];
    if (deviceId >= 0 && deviceId < [devices count]) {
        NSDictionary *device = devices[deviceId];
        NSString *type = device[@"type"];
        
        if ([type isEqualToString:@"source"]) {
            MIDIEndpointRef source = MIDIGetSource(deviceId);
            OSStatus status = MIDIPortDisconnectSource(_inputPort, source);
            if (status == noErr) {
                [self.connectedDevices removeObjectForKey:@(deviceId)];
                return YES;
            }
        }
    }
    return NO;
}

- (BOOL)isDeviceConnected:(int)deviceId {
    return [self.connectedDevices[@(deviceId)] boolValue];
}

- (void)reconnectAllDevices {
    if (!_midiClient || !_inputPort) {
        return;
    }
    
    NSLog(@"[MIDI DEBUG] 🔄 开始重新连接所有MIDI设备...");
    
    // 清空当前连接状态
    [self.connectedDevices removeAllObjects];
    
    // 重新连接所有MIDI输入设备
    ItemCount source_count = MIDIGetNumberOfSources();
    int connected_count = 0;
    
    for (ItemCount i = 0; i < source_count; i++) {
        MIDIEndpointRef source = MIDIGetSource(i);
        
        // 获取设备名称用于调试
        CFStringRef name;
        OSStatus name_status = MIDIObjectGetStringProperty(source, kMIDIPropertyName, &name);
        NSString *deviceName = @"Unknown Device";
        if (name_status == noErr) {
            deviceName = (__bridge NSString *)name;
        }
        
        // 连接到设备
        OSStatus status = MIDIPortConnectSource(_inputPort, source, (__bridge void *)self);
        if (status == noErr) {
            connected_count++;
            [self.connectedDevices setObject:@YES forKey:@(i)];
            NSLog(@"[MIDI DEBUG] ✅ 重新连接MIDI设备 %d: %@", (int)i, deviceName);
        } else {
            NSLog(@"[MIDI DEBUG] ❌ 重新连接MIDI设备 %d 失败, status: %d", (int)i, (int)status);
        }
    }
    
    NSLog(@"[MIDI DEBUG] 🔄 重新连接完成，成功连接 %d 个MIDI输入设备", connected_count);
}

- (BOOL)sendNoteOn:(int)deviceId channel:(int)channel note:(int)note velocity:(int)velocity {
    if (deviceId >= 0 && deviceId < MIDIGetNumberOfDestinations()) {
        MIDIEndpointRef dest = MIDIGetDestination(deviceId);
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        
        Byte data[3] = {(Byte)(0x90 | (channel & 0x0F)), (Byte)(note & 0x7F), (Byte)(velocity & 0x7F)};
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, 0, 3, data);
        
        return MIDISend(_outputPort, dest, &packetList) == noErr;
    }
    return NO;
}

- (BOOL)sendNoteOff:(int)deviceId channel:(int)channel note:(int)note {
    if (deviceId >= 0 && deviceId < MIDIGetNumberOfDestinations()) {
        MIDIEndpointRef dest = MIDIGetDestination(deviceId);
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        
        Byte data[3] = {(Byte)(0x80 | (channel & 0x0F)), (Byte)(note & 0x7F), 0x00};
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, 0, 3, data);
        
        return MIDISend(_outputPort, dest, &packetList) == noErr;
    }
    return NO;
}

- (BOOL)sendControlChange:(int)deviceId channel:(int)channel controller:(int)controller value:(int)value {
    if (deviceId >= 0 && deviceId < MIDIGetNumberOfDestinations()) {
        MIDIEndpointRef dest = MIDIGetDestination(deviceId);
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        
        Byte data[3] = {(Byte)(0xB0 | (channel & 0x0F)), (Byte)(controller & 0x7F), (Byte)(value & 0x7F)};
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, 0, 3, data);
        
        return MIDISend(_outputPort, dest, &packetList) == noErr;
    }
    return NO;
}

- (BOOL)sendProgramChange:(int)deviceId channel:(int)channel program:(int)program {
    if (deviceId >= 0 && deviceId < MIDIGetNumberOfDestinations()) {
        MIDIEndpointRef dest = MIDIGetDestination(deviceId);
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        
        Byte data[2] = {(Byte)(0xC0 | (channel & 0x0F)), (Byte)(program & 0x7F)};
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, 0, 2, data);
        
        return MIDISend(_outputPort, dest, &packetList) == noErr;
    }
    return NO;
}

- (BOOL)sendPitchBend:(int)deviceId channel:(int)channel value:(int)value {
    if (deviceId >= 0 && deviceId < MIDIGetNumberOfDestinations()) {
        MIDIEndpointRef dest = MIDIGetDestination(deviceId);
        MIDIPacketList packetList;
        MIDIPacket *packet = MIDIPacketListInit(&packetList);
        
        int bendValue = value + 8192; // 转换为无符号值
        Byte data[3] = {(Byte)(0xE0 | (channel & 0x0F)), (Byte)(bendValue & 0x7F), (Byte)((bendValue >> 7) & 0x7F)};
        packet = MIDIPacketListAdd(&packetList, sizeof(packetList), packet, 0, 3, data);
        
        return MIDISend(_outputPort, dest, &packetList) == noErr;
    }
    return NO;
}

// 注入MIDI事件到Godot Input系统的方法实现
// 改为使用 Ref<InputEventMIDI> 注入
- (void)injectNoteOnWithChannel:(int)channel note:(int)note velocity:(int)velocity {
    Ref<InputEventMIDI> event;
    event.instantiate();
    event->set_channel(channel);
    event->set_pitch(note);
    event->set_velocity(velocity);
    event->set_message((MIDIMessage)0x90);
    Input::get_singleton()->parse_input_event(event);
}

- (void)injectNoteOffWithChannel:(int)channel note:(int)note velocity:(int)velocity {
    Ref<InputEventMIDI> event;
    event.instantiate();
    event->set_channel(channel);
    event->set_pitch(note);
    event->set_velocity(velocity);
    event->set_message((MIDIMessage)0x80);
    Input::get_singleton()->parse_input_event(event);
}

- (void)injectControlChangeWithChannel:(int)channel controller:(int)controller value:(int)value {
    Ref<InputEventMIDI> event;
    event.instantiate();
    event->set_channel(channel);
    event->set_controller_number(controller);
    event->set_controller_value(value);
    event->set_message((MIDIMessage)0xB0);
    Input::get_singleton()->parse_input_event(event);
}

- (void)injectProgramChangeWithChannel:(int)channel program:(int)program {
    Ref<InputEventMIDI> event;
    event.instantiate();
    event->set_channel(channel);
    event->set_instrument(program);
    event->set_message((MIDIMessage)0xC0);
    Input::get_singleton()->parse_input_event(event);
}

- (void)injectPitchBendWithChannel:(int)channel value:(int)value {
    Ref<InputEventMIDI> event;
    event.instantiate();
    event->set_channel(channel);
    event->set_pressure(value);
    event->set_message((MIDIMessage)0xE0);
    Input::get_singleton()->parse_input_event(event);
}

@end





// C接口函数实现
void midi_plugin_init(void) {
    if (!g_midiPlugin) {
        g_midiPlugin = [[MIDIPlugin alloc] init];
    }
}

void midi_plugin_cleanup(void) {
    if (g_midiPlugin) {
        g_midiPlugin = nil;
    }
}

int midi_get_connected_inputs_count(void) {
    if (!g_midiPlugin) return 0;
    
    NSArray *devices = [g_midiPlugin getMidiDevices];
    int count = 0;
    for (NSDictionary *device in devices) {
        if ([device[@"type"] isEqualToString:@"source"]) {
            count++;
        }
    }
    return count;
}

const char* midi_get_input_name(int index) {
    if (!g_midiPlugin) return NULL;
    
    NSArray *devices = [g_midiPlugin getMidiDevices];
    int sourceIndex = 0;
    for (NSDictionary *device in devices) {
        if ([device[@"type"] isEqualToString:@"source"]) {
            if (sourceIndex == index) {
                NSString *name = device[@"name"];
                return [name UTF8String];
            }
            sourceIndex++;
        }
    }
    return NULL;
}

void midi_refresh_devices(void) {
    if (g_midiPlugin) {
        [g_midiPlugin reconnectAllDevices];
    }
}

int midi_get_device_count(void) {
    if (!g_midiPlugin) return 0;
    
    NSArray *devices = [g_midiPlugin getMidiDevices];
    int count = (int)[devices count];
    NSLog(@"[MIDI] Found %d devices", count);
    
  
    
    return count;
}

const char* midi_get_device_name(int deviceId) {
    if (!g_midiPlugin) return NULL;
    
    NSDictionary *deviceInfo = [g_midiPlugin getDeviceInfo:deviceId];
    NSString *name = deviceInfo[@"name"];
    if (name) {
        return [name UTF8String];
    }
    return NULL;
}

int midi_get_device_type(int deviceId) {
    if (!g_midiPlugin) return 0;
    
    NSDictionary *deviceInfo = [g_midiPlugin getDeviceInfo:deviceId];
    NSString *type = deviceInfo[@"type"];
    if ([type isEqualToString:@"source"]) {
        return 1; // 输入设备
    } else if ([type isEqualToString:@"destination"]) {
        return 2; // 输出设备
    }
    return 0; // 未知类型
}

BOOL midi_connect_device(int deviceId) {
    if (!g_midiPlugin) return NO;
    return [g_midiPlugin connectDevice:deviceId];
}

BOOL midi_disconnect_device(int deviceId) {
    if (!g_midiPlugin) return NO;
    return [g_midiPlugin disconnectDevice:deviceId];
}

BOOL midi_is_device_connected(int deviceId) {
    if (!g_midiPlugin) return NO;
    return [g_midiPlugin isDeviceConnected:deviceId];
}

BOOL midi_send_note_on(int deviceId, int channel, int note, int velocity) {
    if (!g_midiPlugin) return NO;
    return [g_midiPlugin sendNoteOn:deviceId channel:channel note:note velocity:velocity];
}

BOOL midi_send_note_off(int deviceId, int channel, int note) {
    if (!g_midiPlugin) return NO;
    return [g_midiPlugin sendNoteOff:deviceId channel:channel note:note];
}

BOOL midi_send_control_change(int deviceId, int channel, int controller, int value) {
    if (!g_midiPlugin) return NO;
    return [g_midiPlugin sendControlChange:deviceId channel:channel controller:controller value:value];
}

BOOL midi_send_program_change(int deviceId, int channel, int program) {
    if (!g_midiPlugin) return NO;
    return [g_midiPlugin sendProgramChange:deviceId channel:channel program:program];
}

BOOL midi_send_pitch_bend(int deviceId, int channel, int value) {
    if (!g_midiPlugin) return NO;
    return [g_midiPlugin sendPitchBend:deviceId channel:channel value:value];
}

void midi_set_message_callback(MIDIMessageCallback callback) {
    // 这个回调现在通过 InputEventMIDI 直接注入到 Godot Input 系统
}

void midi_set_device_changed_callback(MIDIDeviceChangedCallback callback) {
    // 设备变化现在通过 midi_notify_callback 自动处理
}

// Godot插件入口函数实现
void godot_plugin_init() {
    NSLog(@"[MidiPlugin] godot_plugin_init called");
    midi_plugin_init();
    NSLog(@"[MidiPlugin] MIDI plugin initialized");
}

void godot_plugin_deinit() {
    NSLog(@"[MidiPlugin] godot_plugin_deinit called");
    midi_plugin_cleanup();
    NSLog(@"[MidiPlugin] MIDI plugin cleaned up");
} 
