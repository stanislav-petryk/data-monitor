#include <Cocoa/Cocoa.h>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <mach/mach.h>
#include <sstream>
#include <string>
#include <thread>

std::string execCommand(const char *cmd) {
  char buffer[128];
  std::string result = "";
  FILE *pipe = popen(cmd, "r");
  if (!pipe)
    return "Error";
  while (fgets(buffer, sizeof(buffer), pipe) != nullptr) {
    result += buffer;
  }
  pclose(pipe);
  result.erase(result.find_last_not_of("\n") + 1);
  return result;
}

std::string getBatteryPercent() {
  return execCommand("pmset -g batt | grep -Eo '\\d+%' | head -1");
}

std::string getBatteryMaxCapacity() {
  return execCommand(
      "system_profiler SPPowerDataType | grep 'Maximum Capacity'");
}

std::string getBatteryTemp() {
  std::string temp = execCommand(
      "ioreg -rn AppleSmartBattery | grep -i Temperature | awk '{print $3}'");
  temp = temp.erase(temp.find_last_not_of(' ') + 1);
  temp = temp.substr(temp.size() - 4);
  temp = std::to_string(stod(temp) / 100).substr(0, 4);
  return temp;
}

int getCPUUsage() {
  host_cpu_load_info_data_t cpuInfo;
  mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
  kern_return_t kr = host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO,
                                     (host_info_t)&cpuInfo, &count);

  if (kr != KERN_SUCCESS)
    return -1.0;

  static unsigned long long lastUser = 0, lastSystem = 0, lastIdle = 0,
                            lastNice = 0;

  unsigned long long user = cpuInfo.cpu_ticks[CPU_STATE_USER];
  unsigned long long system = cpuInfo.cpu_ticks[CPU_STATE_SYSTEM];
  unsigned long long idle = cpuInfo.cpu_ticks[CPU_STATE_IDLE];
  unsigned long long nice = cpuInfo.cpu_ticks[CPU_STATE_NICE];

  unsigned long long userDiff = user - lastUser;
  unsigned long long systemDiff = system - lastSystem;
  unsigned long long idleDiff = idle - lastIdle;
  unsigned long long niceDiff = nice - lastNice;

  lastUser = user;
  lastSystem = system;
  lastIdle = idle;
  lastNice = nice;

  unsigned long long totalTicks = userDiff + systemDiff + idleDiff + niceDiff;

  if (totalTicks == 0)
    return 0.0;

  double cpuUsage =
      (double)(userDiff + systemDiff + niceDiff) / (double)totalTicks * 100.0;
  return static_cast<int>(cpuUsage);
}

@interface StatusApp : NSObject
@property(strong) NSStatusItem *statusItem;
- (void)setupStatusItem;
- (void)quitApp:(id)sender;
@end

@implementation StatusApp

- (void)setupStatusItem {
  self.statusItem = [[NSStatusBar systemStatusBar]
      statusItemWithLength:NSVariableStatusItemLength];

  NSImage *icon = [[NSImage alloc]
      initWithContentsOfFile:[[NSBundle mainBundle]
                                 pathForResource:@"DataMonitorIcon"
                                          ofType:@"png"]];
  if (!icon)
    NSLog(@"Icon not found!");
  [icon setSize:NSMakeSize(23, 23)];
  self.statusItem.button.image = icon;

  NSMenu *menu = [[NSMenu alloc] init];
  NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                    action:@selector(quitApp:)
                                             keyEquivalent:@""];
  quitItem.target = self;
  [menu addItem:quitItem];

  self.statusItem.menu = menu;
}

- (void)quitApp:(id)sender {
  [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSApplication *app = [NSApplication sharedApplication];

    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    NSRect screenF = [[NSScreen mainScreen] frame];
    CGFloat windowWidth = 100;
    CGFloat windowHeight = 120;
    CGFloat offsetFromTop = 835;
    CGFloat offsetFromLeft = 1345;

    NSRect frame = NSMakeRect(offsetFromLeft, NSMaxY(screenF) - windowHeight,
                              windowWidth, windowHeight);

    NSWindow *window =
        [[NSWindow alloc] initWithContentRect:frame
                                    styleMask:NSWindowStyleMaskBorderless
                                      backing:NSBackingStoreBuffered
                                        defer:NO];

    [window setLevel:NSStatusWindowLevel];
    [window setOpaque:NO];
    [window setBackgroundColor:[NSColor colorWithWhite:0 alpha:0.0]];
    [window setReleasedWhenClosed:NO];
    [window setIgnoresMouseEvents:YES];
    [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];

    NSTextField *label =
        [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 100, 120)];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [label setTextColor:[NSColor whiteColor]];
    [label setFont:[NSFont systemFontOfSize:12]];
    [window.contentView addSubview:label];

    NSScreen *screen = [NSScreen mainScreen];
    NSRect screenFrame = [screen frame];
    NSPoint newOrigin =
        NSMakePoint(NSMinX(frame), NSMinY(frame) - offsetFromTop);
    [window setFrameOrigin:newOrigin];

    [window makeKeyAndOrderFront:nil];

    StatusApp *manager = [[StatusApp alloc] init];
    [manager setupStatusItem];

    std::thread([label]() {
      while (true) {
        if (true) {
        }
        std::stringstream ss;
        ss << "Battery: " << getBatteryPercent() << std::endl;
        ss << "MaxCap: " << getBatteryMaxCapacity().substr(28) << std::endl;
        ss << "Temp: " << getBatteryTemp() << "°C\n";
        ss << "CPU Load: " << getCPUUsage() << "%";

        NSString *nsStr = [NSString stringWithUTF8String:ss.str().c_str()];
        dispatch_async(dispatch_get_main_queue(), ^{
          [label setStringValue:nsStr];
        });
        std::this_thread::sleep_for(std::chrono::seconds(1));
      }
    }).detach();

    [app run];
  }
  return 0;
}
