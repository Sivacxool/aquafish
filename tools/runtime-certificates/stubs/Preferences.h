#pragma once
#include "Arduino.h"
#include <map>
inline std::map<std::string,std::string> mockNvs;
inline bool mockFailWrites=false,mockStorageAvailable=true;
inline size_t mockWriteCount=0;
class Preferences {
  std::string prefix_;
public:
  bool begin(const char *name,bool){prefix_=std::string(name)+":";return mockStorageAvailable;}
  bool isKey(const char *key){return mockNvs.count(prefix_+key)>0;}
  String getString(const char *key,const char *fallback){auto it=mockNvs.find(prefix_+key);return it==mockNvs.end()?String(fallback):String(it->second);}
  size_t putString(const char *key,const String &value){if(mockFailWrites)return 0;mockNvs[prefix_+key]=value.c_str();mockWriteCount++;return value.length();}
};
