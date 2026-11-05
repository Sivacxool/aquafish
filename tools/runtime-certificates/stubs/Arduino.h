#pragma once
// Host-only adapters. Firmware compiles against the real Arduino/ESP-IDF APIs.
#include <string>
#include <cstring>
#include <cctype>
#include <cstdlib>
#include <cstdio>
#include <ctime>
#include <algorithm>
#include <cstdint>
#define ARDUINOJSON_ENABLE_ARDUINO_STRING 1
#define ARDUINOJSON_ENABLE_ARDUINO_STREAM 0
#define ARDUINOJSON_ENABLE_ARDUINO_PRINT 0
class String {
  std::string value_;
public:
  String()=default;
  String(const char *s):value_(s?s:""){}
  String(const std::string &s):value_(s){}
  const char *c_str()const{return value_.c_str();}
  size_t length()const{return value_.size();}
  bool isEmpty()const{return value_.empty();}
  void reserve(size_t n){value_.reserve(n);}
  bool concat(const char *s){if(s)value_+=s;return true;}
  String &operator=(const char *s){value_=s?s:"";return *this;}
  String &operator+=(char c){value_+=c;return *this;}
  String &operator+=(const String &s){value_+=s.value_;return *this;}
  String substring(size_t first,size_t last=std::string::npos)const{return value_.substr(first,last==std::string::npos?last:last-first);}
  void toUpperCase(){for(char &c:value_)c=(char)std::toupper((unsigned char)c);}
  void replace(const char *oldValue,const char *newValue){size_t at=0;const size_t oldSize=std::strlen(oldValue),newSize=std::strlen(newValue);while((at=value_.find(oldValue,at))!=std::string::npos){value_.replace(at,oldSize,newValue);at+=newSize;}}
  auto begin()const{return value_.begin();}auto end()const{return value_.end();}
  friend String operator+(const String &a,const String &b){return a.value_+b.value_;}
  friend bool operator==(const String &a,const String &b){return a.value_==b.value_;}
  friend bool operator!=(const String &a,const String &b){return !(a==b);}
};
#ifdef _WIN32
inline int setenv(const char *key,const char *value,int){return _putenv_s(key,value);}
inline void tzset(){_tzset();}
inline std::tm *gmtime_r(const std::time_t *value,std::tm *out){return gmtime_s(out,value)==0?out:nullptr;}
#endif
