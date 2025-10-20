#include <Cocoa/Cocoa.h>
#include <chrono>
#include <cstdio>
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
             "system_profiler SPPowerDataType | grep 'Maximum Capacity'")
      .substr(28);
}

std::string getBatteryTemp() {
  std::string temp = execCommand(
      "ioreg -rn AppleSmartBattery | grep -i Temperature | awk '{print $3}'");
  temp = temp.erase(temp.find_last_not_of(' ') + 1);
  temp = temp.substr(temp.size() - 4);
  temp = std::to_string(stod(temp) / 100).substr(0, 4);
  return temp;
}

std::string getGPUUsage() {
  std::string cpuUsage = execCommand("sudo /usr/local/bin/gpu_idle");
  cpuUsage = std::to_string(std::ceil(100 - stod(cpuUsage.substr(0, 5))));
  int dotPosition = cpuUsage.find('.');

  return cpuUsage.substr(0, dotPosition) + "%";
}

int getCPUUsage() {
  natural_t cpuCount;
  processor_info_array_t infoArray;
  mach_msg_type_number_t infoCount;
  static processor_info_array_t prevInfoArray = NULL;
  static mach_msg_type_number_t prevInfoCount = 0;
  static natural_t prevCPUCount = 0;

  kern_return_t kr =
      host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount,
                          &infoArray, &infoCount);
  if (kr != KERN_SUCCESS)
    return -1;

  float totalUsage = 0;
  for (unsigned i = 0; i < cpuCount; i++) {
    float user, system, idle, nice;
    if (prevInfoArray) {
      unsigned int index = CPU_STATE_MAX * i;
      user = infoArray[index + CPU_STATE_USER] -
             prevInfoArray[index + CPU_STATE_USER];
      system = infoArray[index + CPU_STATE_SYSTEM] -
               prevInfoArray[index + CPU_STATE_SYSTEM];
      idle = infoArray[index + CPU_STATE_IDLE] -
             prevInfoArray[index + CPU_STATE_IDLE];
      nice = infoArray[index + CPU_STATE_NICE] -
             prevInfoArray[index + CPU_STATE_NICE];
    }
    else {
      unsigned int index = CPU_STATE_MAX * i;
      user = infoArray[index + CPU_STATE_USER];
      system = infoArray[index + CPU_STATE_SYSTEM];
      idle = infoArray[index + CPU_STATE_IDLE];
      nice = infoArray[index + CPU_STATE_NICE];
    }

    float total = user + system + idle + nice;
    totalUsage += (user + system + nice) / total * 100.0f;
  }

  // очистка попередніх даних
  if (prevInfoArray)
    vm_deallocate(mach_task_self(), (vm_address_t)prevInfoArray,
                  sizeof(integer_t) * prevInfoCount);

  prevInfoArray = infoArray;
  prevInfoCount = infoCount;
  prevCPUCount = cpuCount;

  return (int)(totalUsage / cpuCount);
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
    CGFloat offsetFromTop = 820;
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
      int i = 0;
      __block std::string gpuUsage;
      std::string battery = getBatteryPercent();
      std::string maxCap = getBatteryMaxCapacity();
      std::string temp = getBatteryTemp();

      while (true) {
        std::stringstream ss;
        if (i % 3 == 0) {
          dispatch_async(
              dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                gpuUsage = getGPUUsage();
              });
        }
        if (i == 15) {
          battery = getBatteryPercent();
          maxCap = getBatteryMaxCapacity();
          temp = getBatteryTemp();
          i = 0;
        }
        i++;
        ss << "Battery: " << battery << std::endl;
        ss << "MaxCap: " << maxCap << std::endl;
        ss << "Temp: " << temp << "°C\n";
        ss << "CPU Load: " << getCPUUsage() << "%" << std::endl;
        ss << "GPU Load: " << gpuUsage;

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
