// Desktop stub for the P2P collaboration module.
// ReverieCoreCollab.cpp depends on libdatachannel (rtc/rtc.hpp) which is not shipped on Windows.
// In non-collab mode the engine only calls these guards/notifiers; they must behave as
// "everything allowed, nothing to sync" so that normal single-user editing is unaffected.
#include "ReverieCore.h"

bool ReverieCore::collabCanEditLayerIndex(int) const { return true; }
bool ReverieCore::collabCanEditLayer(int) const { return true; }
bool ReverieCore::collabCanEditCurrentLayer() const { return true; }
bool ReverieCore::collabCanEditBackground() const { return true; }
bool ReverieCore::collabCanModifyLayerProps(int) const { return true; }
bool ReverieCore::collabCanManageLayerOwnership(int) const { return true; }
bool ReverieCore::collabCanInsertIntoGroup(int) const { return true; }
bool ReverieCore::collabCanDeleteLayer(int) const { return true; }
bool ReverieCore::collabCanCopySubtree(int) const { return true; }
bool ReverieCore::collabIsNodeTypeSupported(int) const { return true; }
bool ReverieCore::collabIsHost() const { return false; }
bool ReverieCore::collabCanUndo() const { return false; }
bool ReverieCore::collabCanRedo() const { return false; }
int ReverieCore::collabUndoCount() const { return 0; }
int ReverieCore::collabRedoCount() const { return 0; }
bool ReverieCore::collabUndo() { return false; }
bool ReverieCore::collabRedo() { return false; }

KisPaintDeviceSP ReverieCore::collabSnapshotLayerBefore(int) const { return KisPaintDeviceSP(); }

void ReverieCore::collabRecordLayerPixelEdit(int, const KisPaintDeviceSP &, const QRect &, bool) {}
void ReverieCore::collabRecordLayerPixelBatch(const QVector<QPair<int, KisPaintDeviceSP>> &,
                                              const QVector<QRect> &, bool) {}
void ReverieCore::collabEmitLayerOp(int, int, const QString &, double, int) {}
void ReverieCore::collabEmitLayerTreeAdded(int) {}
void ReverieCore::collabEmitLayerMoved(const QVector<KisNode *> &) {}
void ReverieCore::collabSyncAddedLayerPlacement(int, int, const QString &, int) {}
void ReverieCore::collabAdjustProtectedInsertPosition(KisImageSP, KisNodeSP &, KisNodeSP &) const {}
void ReverieCore::collabResetDocumentState() {}
void ReverieCore::collabOnLocalStrokeBegin(int) {}
void ReverieCore::collabOnLocalStrokeEnd(const QRect &) {}
void ReverieCore::collabOnLocalStrokeCancel() {}
void ReverieCore::collabOnLocalStrokeFlushed() {}
void ReverieCore::collabStopSession() {}
void ReverieCore::setProjectCollabMeta(bool, const QString &) {}
