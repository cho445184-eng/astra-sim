#!/bin/bash
# Creates the feeder_v3 compatibility layer for ASTRA-sim.
# The chakra submodule's expected commit (450b2187...) was force-pushed away.
# The ASTRA-sim code expects Chakra::FeederV3:: namespace with additional APIs
# (DependancyResolver, template accessors, has_attr/get_attr) that don't exist
# in the current chakra feeder. This script creates wrapper classes.
set -e

CHAKRA_DIR="${1:-extern/graph_frontend/chakra}"
V3_DIR="${CHAKRA_DIR}/src/feeder_v3"

if [ -f "${V3_DIR}/et_feeder.cpp" ] && [ -f "${V3_DIR}/et_feeder_node.cpp" ]; then
  exit 0
fi

mkdir -p "${V3_DIR}"

# --- et_feeder_node.h ---
cat > "${V3_DIR}/et_feeder_node.h" << 'HEADER_NODE'
#pragma once
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include "et_def.pb.h"

namespace Chakra {
namespace FeederV3 {

using ChakraAttr = ChakraProtoMsg::AttributeProto;

class ETFeederNode {
 public:
  ETFeederNode(std::shared_ptr<ChakraProtoMsg::Node> node);
  std::shared_ptr<ChakraProtoMsg::Node> getChakraNode();
  void addChild(std::shared_ptr<ETFeederNode> node);
  std::vector<std::shared_ptr<ETFeederNode>> getChildren();
  void addDepUnresolvedParentID(uint64_t node_id);
  std::vector<uint64_t> getDepUnresolvedParentIDs();
  void setDepUnresolvedParentIDs(std::vector<uint64_t> const& ids);
  const ChakraProtoMsg::AttributeProto& get_other_attr(const std::string& n) const;
  bool has_other_attr(const std::string& n) const;
  bool has_attr(const std::string& n) const;
  template <typename T> T get_attr(const std::string& n) const {
    return static_cast<T>(get_other_attr(n));
  }
  const ChakraProtoMsg::AttributeProto& get_attr_msg(const std::string& n) const {
    return get_other_attr(n);
  }
  uint64_t id();
  std::string name();
  bool is_cpu_op();
  template <typename T> T is_cpu_op(T) { return static_cast<T>(is_cpu_op_); }
  ChakraProtoMsg::NodeType type();
  uint64_t runtime();
  uint64_t num_ops();
  template <typename T> T num_ops() { return static_cast<T>(num_ops_); }
  uint32_t tensor_loc();
  uint64_t tensor_size();
  template <typename T> T tensor_size() { return static_cast<T>(tensor_size_); }
  ChakraProtoMsg::CollectiveCommType comm_type();
  template <typename T> T comm_type() { return static_cast<T>(comm_type_); }
  uint32_t comm_priority();
  template <typename T> T comm_priority() { return static_cast<T>(comm_priority_); }
  uint64_t comm_size();
  template <typename T> T comm_size() { return static_cast<T>(comm_size_); }
  uint32_t comm_src();
  uint32_t comm_src(int default_id);
  template <typename T> T comm_src() { return static_cast<T>(comm_src_); }
  template <typename T> T comm_src(T) { return static_cast<T>(comm_src_); }
  uint32_t comm_dst();
  template <typename T> T comm_dst() { return static_cast<T>(comm_dst_); }
  template <typename T> T comm_dst(T) { return static_cast<T>(comm_dst_); }
  uint32_t comm_tag();
  template <typename T> T comm_tag() { return static_cast<T>(comm_tag_); }
  std::string pg_name();
  template <typename T> T pg_name(T d) { return pg_name_.empty() ? d : static_cast<T>(pg_name_); }
  std::string get_inputs_values() const;
  std::string get_inputs_shapes() const;
  std::string get_inputs_types() const;
  std::string get_outputs_values() const;
  std::string get_outputs_shapes() const;
  std::string get_outputs_types() const;

 private:
  std::shared_ptr<ChakraProtoMsg::Node> node_{nullptr};
  std::unordered_set<std::shared_ptr<ETFeederNode>> children_set_{};
  std::vector<std::shared_ptr<ETFeederNode>> children_vec_{};
  std::vector<uint64_t> dep_unresolved_parent_ids_{};
  std::unordered_map<std::string, const ChakraProtoMsg::AttributeProto&> other_attrs_{};
  uint64_t id_; std::string name_; bool is_cpu_op_; uint64_t runtime_;
  uint64_t num_ops_{0}; uint32_t tensor_loc_{0}; uint64_t tensor_size_{0};
  ChakraProtoMsg::CollectiveCommType comm_type_{};
  uint32_t comm_priority_{0}; uint64_t comm_size_{0};
  uint32_t comm_src_{0}; uint32_t comm_dst_{0}; uint32_t comm_tag_{0};
  std::string pg_name_;
  std::string inputs_values_, inputs_shapes_, inputs_types_;
  std::string outputs_values_, outputs_shapes_, outputs_types_;
};

} // namespace FeederV3
using ETFeederNode = FeederV3::ETFeederNode;
} // namespace Chakra
HEADER_NODE

# --- et_feeder.h ---
cat > "${V3_DIR}/et_feeder.h" << 'HEADER_FEEDER'
#pragma once
#include <memory>
#include <queue>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include "et_feeder_node.h"
#include "protoio.hh"

namespace Chakra {
namespace FeederV3 {

class ETFeeder;

struct CompareNodes {
  bool operator()(const std::shared_ptr<ETFeederNode>& l,
                  const std::shared_ptr<ETFeederNode>& r) const {
    return l->getChakraNode()->id() > r->getChakraNode()->id();
  }
};

class DependancyResolver {
 public:
  void take_node(uint64_t node_id);
  void finish_node(uint64_t node_id);
  const std::unordered_set<uint64_t>& get_dependancy_free_nodes() const;
  const std::unordered_set<uint64_t>& get_ongoing_nodes() const;
 private:
  std::unordered_set<uint64_t> dep_free_nodes_{};
  std::unordered_set<uint64_t> ongoing_nodes_{};
  ETFeeder* feeder_{nullptr};
  friend class ETFeeder;
};

class ETFeeder {
 public:
  ETFeeder(std::string filename);
  ~ETFeeder();
  DependancyResolver& getDependancyResolver();
  void addNode(std::shared_ptr<ETFeederNode> node);
  void removeNode(uint64_t node_id);
  bool hasNodesToIssue();
  std::shared_ptr<ETFeederNode> getNextIssuableNode();
  void pushBackIssuableNode(uint64_t node_id);
  std::shared_ptr<ETFeederNode> lookupNode(uint64_t node_id);
  void freeChildrenNodes(uint64_t node_id);
  void readGlobalMetadata();
  std::shared_ptr<ETFeederNode> readNode();
  void readNextWindow();
  void resolveDep();
 private:
  ProtoInputStream trace_;
  const uint32_t window_size_;
  bool et_complete_;
  std::unordered_map<uint64_t, std::shared_ptr<ETFeederNode>> dep_graph_{};
  std::unordered_set<uint64_t> dep_free_node_id_set_{};
  std::priority_queue<std::shared_ptr<ETFeederNode>,
      std::vector<std::shared_ptr<ETFeederNode>>, CompareNodes> dep_free_node_queue_{};
  std::unordered_set<std::shared_ptr<ETFeederNode>> dep_unresolved_node_set_{};
  DependancyResolver dep_resolver_;
};

} // namespace FeederV3
using ETFeeder = FeederV3::ETFeeder;
} // namespace Chakra
HEADER_FEEDER

# --- et_feeder_node.cpp ---
cat > "${V3_DIR}/et_feeder_node.cpp" << 'SRC_NODE'
#include "et_feeder_node.h"
using namespace std;
namespace Chakra { namespace FeederV3 {

ETFeederNode::ETFeederNode(shared_ptr<ChakraProtoMsg::Node> node) {
  node_ = node; id_ = node->id(); name_ = node->name();
  runtime_ = node->duration_micros(); is_cpu_op_ = 0;
  if (node->has_inputs()) {
    inputs_values_ = static_cast<string>(node->inputs().values());
    inputs_shapes_ = static_cast<string>(node->inputs().shapes());
    inputs_types_ = static_cast<string>(node->inputs().types());
  }
  if (node->has_outputs()) {
    outputs_values_ = static_cast<string>(node->outputs().values());
    outputs_shapes_ = static_cast<string>(node->outputs().shapes());
    outputs_types_ = static_cast<string>(node->outputs().types());
  }
  for (const auto& attr : node->attr()) {
    const string& n = attr.name();
    if (n=="is_cpu_op") is_cpu_op_=static_cast<bool>(attr.bool_val());
    else if (n=="num_ops") num_ops_=static_cast<uint64_t>(attr.int64_val());
    else if (n=="tensor_size") tensor_size_=attr.uint64_val();
    else if (n=="comm_type") comm_type_=static_cast<ChakraProtoMsg::CollectiveCommType>(attr.int64_val());
    else if (n=="comm_priority") comm_priority_=static_cast<uint32_t>(attr.int32_val());
    else if (n=="comm_size") comm_size_=static_cast<uint64_t>(attr.int64_val());
    else if (n=="comm_src") comm_src_=static_cast<uint32_t>(attr.int32_val());
    else if (n=="comm_dst") comm_dst_=static_cast<uint32_t>(attr.int32_val());
    else if (n=="comm_tag") comm_tag_=static_cast<uint32_t>(attr.int32_val());
    else if (n=="pg_name") pg_name_=static_cast<string>(attr.string_val());
    else other_attrs_.emplace(n, attr);
  }
}
shared_ptr<ChakraProtoMsg::Node> ETFeederNode::getChakraNode() { return node_; }
void ETFeederNode::addChild(shared_ptr<ETFeederNode> n) {
  if (children_set_.find(n)!=children_set_.end()) return;
  children_vec_.emplace_back(n); children_set_.emplace(n);
}
vector<shared_ptr<ETFeederNode>> ETFeederNode::getChildren() { return children_vec_; }
void ETFeederNode::addDepUnresolvedParentID(uint64_t id) { dep_unresolved_parent_ids_.emplace_back(id); }
vector<uint64_t> ETFeederNode::getDepUnresolvedParentIDs() { return dep_unresolved_parent_ids_; }
void ETFeederNode::setDepUnresolvedParentIDs(vector<uint64_t> const& ids) { dep_unresolved_parent_ids_=ids; }
const ChakraProtoMsg::AttributeProto& ETFeederNode::get_other_attr(const string& n) const {
  if (has_other_attr(n)) return other_attrs_.at(n);
  throw runtime_error("Asked for attr \""+n+"\" from node "+to_string(id_)+", which do not exist");
}
bool ETFeederNode::has_other_attr(const string& n) const { return other_attrs_.find(n)!=other_attrs_.end(); }
bool ETFeederNode::has_attr(const string& n) const { return has_other_attr(n); }
uint64_t ETFeederNode::id() { return id_; }
string ETFeederNode::name() { return name_; }
bool ETFeederNode::is_cpu_op() { return is_cpu_op_; }
ChakraProtoMsg::NodeType ETFeederNode::type() { return node_->type(); }
uint64_t ETFeederNode::runtime() { return runtime_; }
uint64_t ETFeederNode::num_ops() { return num_ops_; }
uint32_t ETFeederNode::tensor_loc() { return tensor_loc_; }
uint64_t ETFeederNode::tensor_size() { return tensor_size_; }
ChakraProtoMsg::CollectiveCommType ETFeederNode::comm_type() { return comm_type_; }
uint32_t ETFeederNode::comm_priority() { return comm_priority_; }
uint64_t ETFeederNode::comm_size() { return comm_size_; }
uint32_t ETFeederNode::comm_src() { return comm_src_; }
uint32_t ETFeederNode::comm_src(int) { return comm_src_; }
uint32_t ETFeederNode::comm_dst() { return comm_dst_; }
uint32_t ETFeederNode::comm_tag() { return comm_tag_; }
string ETFeederNode::pg_name() { return pg_name_; }
string ETFeederNode::get_inputs_values() const { return node_->has_inputs()?inputs_values_:""; }
string ETFeederNode::get_inputs_shapes() const { return node_->has_inputs()?inputs_shapes_:""; }
string ETFeederNode::get_inputs_types() const { return node_->has_inputs()?inputs_types_:""; }
string ETFeederNode::get_outputs_values() const { return node_->has_outputs()?outputs_values_:""; }
string ETFeederNode::get_outputs_shapes() const { return node_->has_outputs()?outputs_shapes_:""; }
string ETFeederNode::get_outputs_types() const { return node_->has_outputs()?outputs_types_:""; }

}} // namespace Chakra::FeederV3
SRC_NODE

# --- et_feeder.cpp ---
cat > "${V3_DIR}/et_feeder.cpp" << 'SRC_FEEDER'
#include "et_feeder.h"
#include <iostream>
using namespace std;
namespace Chakra { namespace FeederV3 {

ETFeeder::ETFeeder(string filename)
    : trace_(filename), window_size_(4096*256), et_complete_(false) {
  dep_resolver_.feeder_ = this;
  if (!trace_.is_open()) throw runtime_error("Failed to open trace file: "+filename);
  try { readGlobalMetadata(); readNextWindow(); }
  catch (const exception& e) { cerr<<"Error in constructor: "<<e.what()<<endl; throw; }
  for (auto& kv : dep_graph_) {
    if (dep_free_node_id_set_.count(kv.first)) dep_resolver_.dep_free_nodes_.insert(kv.first);
  }
}
ETFeeder::~ETFeeder() {}
DependancyResolver& ETFeeder::getDependancyResolver() { return dep_resolver_; }
void ETFeeder::addNode(shared_ptr<ETFeederNode> node) { dep_graph_[node->getChakraNode()->id()]=node; }
void ETFeeder::removeNode(uint64_t id) {
  dep_graph_.erase(id);
  if (!et_complete_&&(dep_free_node_queue_.size()<window_size_)) readNextWindow();
}
bool ETFeeder::hasNodesToIssue() { return !(dep_graph_.empty()&&dep_free_node_queue_.empty()); }
shared_ptr<ETFeederNode> ETFeeder::getNextIssuableNode() {
  if (dep_free_node_queue_.size()!=0) {
    auto node=dep_free_node_queue_.top();
    dep_free_node_id_set_.erase(node->getChakraNode()->id());
    dep_free_node_queue_.pop(); return node;
  } return nullptr;
}
void ETFeeder::pushBackIssuableNode(uint64_t id) {
  auto node=dep_graph_[id]; dep_free_node_id_set_.emplace(id); dep_free_node_queue_.emplace(node);
}
shared_ptr<ETFeederNode> ETFeeder::lookupNode(uint64_t id) {
  try { return dep_graph_.at(id); }
  catch (const out_of_range& e) { cerr<<"looking for node_id="<<id<<" in dep graph, however, not loaded yet"<<endl; throw(e); }
}
void ETFeeder::freeChildrenNodes(uint64_t node_id) {
  auto node=dep_graph_[node_id];
  for (auto child : node->getChildren()) {
    auto cc=child->getChakraNode();
    for (auto it=cc->mutable_data_deps()->begin(); it!=cc->mutable_data_deps()->end(); ++it) {
      if (*it==static_cast<int64_t>(node_id)) { cc->mutable_data_deps()->erase(it); break; }
    }
    if (cc->data_deps().size()==0) {
      dep_free_node_id_set_.emplace(cc->id()); dep_free_node_queue_.emplace(child);
      dep_resolver_.dep_free_nodes_.insert(cc->id());
    }
  }
}
void ETFeeder::readGlobalMetadata() {
  if (!trace_.is_open()) throw runtime_error("Trace file closed unexpectedly during reading global metadata.");
  auto pkt_msg=make_shared<ChakraProtoMsg::GlobalMetadata>(); trace_.read(*pkt_msg);
}
shared_ptr<ETFeederNode> ETFeeder::readNode() {
  auto pkt_msg=make_shared<ChakraProtoMsg::Node>();
  if (!trace_.read(*pkt_msg)) return nullptr;
  auto node=make_shared<ETFeederNode>(pkt_msg);
  bool dep_unresolved=false;
  for (int i=0; i<pkt_msg->data_deps_size(); ++i) {
    auto parent=dep_graph_.find(pkt_msg->data_deps(i));
    if (parent!=dep_graph_.end()) parent->second->addChild(node);
    else { dep_unresolved=true; node->addDepUnresolvedParentID(pkt_msg->data_deps(i)); }
  }
  if (dep_unresolved) dep_unresolved_node_set_.emplace(node);
  return node;
}
void ETFeeder::resolveDep() {
  for (auto it=dep_unresolved_node_set_.begin(); it!=dep_unresolved_node_set_.end();) {
    auto node=*it; auto ids=node->getDepUnresolvedParentIDs();
    for (auto ii=ids.begin(); ii!=ids.end();) {
      auto p=dep_graph_.find(*ii);
      if (p!=dep_graph_.end()) { p->second->addChild(node); ii=ids.erase(ii); } else ++ii;
    }
    if (ids.size()==0) it=dep_unresolved_node_set_.erase(it);
    else { node->setDepUnresolvedParentIDs(ids); ++it; }
  }
}
void ETFeeder::readNextWindow() {
  if (!trace_.is_open()) throw runtime_error("Trace file closed unexpectedly during reading next window.");
  uint32_t num_read=0;
  do {
    auto new_node=readNode();
    if (new_node==nullptr) { et_complete_=true; break; }
    addNode(new_node); ++num_read; resolveDep();
  } while ((num_read<window_size_)||(dep_unresolved_node_set_.size()!=0));
  for (auto kv : dep_graph_) {
    if ((dep_free_node_id_set_.count(kv.first)==0)&&(kv.second->getChakraNode()->data_deps().size()==0)) {
      dep_free_node_id_set_.emplace(kv.first); dep_free_node_queue_.emplace(kv.second);
    }
  }
}

void DependancyResolver::take_node(uint64_t id) { dep_free_nodes_.erase(id); ongoing_nodes_.insert(id); }
void DependancyResolver::finish_node(uint64_t id) {
  ongoing_nodes_.erase(id); feeder_->freeChildrenNodes(id); feeder_->removeNode(id);
}
const unordered_set<uint64_t>& DependancyResolver::get_dependancy_free_nodes() const { return dep_free_nodes_; }
const unordered_set<uint64_t>& DependancyResolver::get_ongoing_nodes() const { return ongoing_nodes_; }

}} // namespace Chakra::FeederV3
SRC_FEEDER

echo "[setup_chakra_compat.sh] feeder_v3 compatibility layer created."
