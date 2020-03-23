/*
 *   cfadisk.c - CompactFlash fixed disk filter driver
 *
 *   Copyright (c) Hitachi Global Storage Technologies 2003. All rights reserved.
 *
 *   This driver filters IOCTL_STORAGE_QUERY_PROPERTY so that Windows XP can
 *   correctly handle CompactFlash device as a fixed disk.
 *
 * ----------------------------------------------------------------------------------
 *
 *   THIS CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND,
 *   EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO
 *   THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR
 *   A PARTICULAR PURPOSE.
 *
 */

#include "ntddk.h"
#include "ntddscsi.h"
#include "ntdddisk.h"
#include "scsi.h"
#include "stdio.h"


//
// function declarations
//

typedef struct _DEVICE_EXTENSION {
  PDEVICE_OBJECT DeviceObject;
  PDEVICE_OBJECT TargetDeviceObject;
} DEVICE_EXTENSION, *PDEVICE_EXTENSION;

DRIVER_UNLOAD CfaUnload;
VOID CfaUnload(
  IN PDRIVER_OBJECT DriverObject
);

DRIVER_ADD_DEVICE CfaAddDevice;
NTSTATUS CfaAddDevice(
  IN PDRIVER_OBJECT DriverObject,
  IN PDEVICE_OBJECT PhysicalDeviceObject
);

DRIVER_DISPATCH CfaDeviceControl;
NTSTATUS CfaDeviceControl(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
);

DRIVER_DISPATCH CfaDispatchPnp;
NTSTATUS CfaDispatchPnp(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
);

DRIVER_DISPATCH CfaDispatchPower;
NTSTATUS CfaDispatchPower(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
);

DRIVER_DISPATCH CfaShutdownFlush;
NTSTATUS CfaShutdownFlush(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
);

DRIVER_DISPATCH CfaSendToNextDriver;
NTSTATUS CfaSendToNextDriver(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
);


// -----------------

DRIVER_INITIALIZE DriverEntry;
NTSTATUS
DriverEntry(
  IN PDRIVER_OBJECT DriverObject,
  IN PUNICODE_STRING RegistryPath
  )
{
  ULONG n;

  KdPrint(("CfaDisk@DriverEntry - DriverObject = %p\n", DriverObject));

  for(n = 0; n <= IRP_MJ_MAXIMUM_FUNCTION; n++){
    DriverObject->MajorFunction[n] = CfaSendToNextDriver;
  }

  DriverObject->MajorFunction[IRP_MJ_DEVICE_CONTROL] = CfaDeviceControl;

  DriverObject->MajorFunction[IRP_MJ_SHUTDOWN]       = CfaShutdownFlush;
  DriverObject->MajorFunction[IRP_MJ_FLUSH_BUFFERS]  = CfaShutdownFlush;
  DriverObject->MajorFunction[IRP_MJ_PNP]            = CfaDispatchPnp;
  DriverObject->MajorFunction[IRP_MJ_POWER]          = CfaDispatchPower;

  DriverObject->DriverExtension->AddDevice           = CfaAddDevice;
  DriverObject->DriverUnload                         = CfaUnload;

  return(STATUS_SUCCESS);
}



//
// This routine sends the Irp to the lower driver in the driver stack
//
NTSTATUS CfaSendToNextDriver(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
)
{
  PDEVICE_EXTENSION deviceExtension = DeviceObject->DeviceExtension;

  IoSkipCurrentIrpStackLocation(Irp);
  return(IoCallDriver(deviceExtension->TargetDeviceObject, Irp));

}


//
// This routine is called when the device is unloaded.
//
VOID CfaUnload(
  IN PDRIVER_OBJECT DriverObject
)
{
    KdPrint(("CfaUnload\n"));
    ASSERT(DriverObject->DeviceObject);
    return;
}


#define CHECKBOUND  ((size_t)&((*(PSTORAGE_DEVICE_DESCRIPTOR)0).RemovableMedia) + \
                     sizeof((*(PSTORAGE_DEVICE_DESCRIPTOR)0).RemovableMedia))

//
// This routine is called when IOCTL_STORAGE_QUERY_PROPERTY has completed.
//
IO_COMPLETION_ROUTINE CfaQueryPropertyCompletion;
NTSTATUS CfaQueryPropertyCompletion(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp,
  IN PVOID Context
)
{
  UNREFERENCED_PARAMETER(DeviceObject);
  UNREFERENCED_PARAMETER(Context);

  if(Irp->PendingReturned){
    IoMarkIrpPending(Irp);
  }

  if(NT_SUCCESS(Irp->IoStatus.Status)){

    PIO_STACK_LOCATION irpStack = IoGetCurrentIrpStackLocation(Irp);
    ULONG bufferLength = irpStack->Parameters.DeviceIoControl.OutputBufferLength;

    if(bufferLength >= CHECKBOUND){
      PSTORAGE_DEVICE_DESCRIPTOR devdesc = (PSTORAGE_DEVICE_DESCRIPTOR)Irp->AssociatedIrp.SystemBuffer;
      BOOLEAN rmv = devdesc->RemovableMedia;

      DbgPrint("CfaQueryPropertyCompletion: IOCTL_STORAGE_QUERY_PROPERTY completed\n");
      KdPrint(("  Buffer size = %d\n", bufferLength));
      KdPrint(("  Bound = %d\n", CHECKBOUND));
      DbgPrint("  RemovableMedia = %d", rmv);

      if(rmv){
        devdesc->RemovableMedia = 0;
        DbgPrint(" -> %d", devdesc->RemovableMedia);
      }
      DbgPrint("\n");
    }

  }

  return(Irp->IoStatus.Status);
}


//
// This routine is called by the I/O subsystem for device controls.
//
NTSTATUS CfaDeviceControl(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
)
{
  NTSTATUS status;
  ULONG controlCode;
  PIO_STACK_LOCATION irpStack = IoGetCurrentIrpStackLocation(Irp);

  controlCode = irpStack->Parameters.DeviceIoControl.IoControlCode;

  KdPrint(("CfaDeviceControl: control code = %08X\n", controlCode));

  if(IOCTL_STORAGE_QUERY_PROPERTY == controlCode){
    PDEVICE_EXTENSION deviceExtension = DeviceObject->DeviceExtension;
    PSTORAGE_PROPERTY_QUERY prop = (PSTORAGE_PROPERTY_QUERY)Irp->AssociatedIrp.SystemBuffer;
    BOOLEAN hookup = FALSE;

    __try {
      // check if query is for STOREAGE_DEVICE_DESCRIPTOR
      if((StorageDeviceProperty == prop->PropertyId) && (PropertyStandardQuery == prop->QueryType)){
        hookup = TRUE;
      }
    } __except(EXCEPTION_EXECUTE_HANDLER) { ; }

    if(hookup){
      IoCopyCurrentIrpStackLocationToNext(Irp);
      IoSetCompletionRoutine(Irp, CfaQueryPropertyCompletion, (PVOID)0, TRUE, TRUE, TRUE);
      return(IoCallDriver(deviceExtension->TargetDeviceObject, Irp));
    }

  }

  return(CfaSendToNextDriver(DeviceObject, Irp));

}


//
// This routine creates and initializes a new function device object
// for the given physical device object.
//
NTSTATUS CfaAddDevice(
  IN PDRIVER_OBJECT DriverObject,
  IN PDEVICE_OBJECT PhysicalDeviceObject
)
{
  NTSTATUS status;
  PDEVICE_OBJECT filterDeviceObject;
  PDEVICE_EXTENSION deviceExtension;

  KdPrint(("CfaAddDevice: PDO = %p\n", PhysicalDeviceObject));

  //
  // create a filter device object
  //
  status = IoCreateDevice(DriverObject,
                          sizeof(DEVICE_EXTENSION),
                          NULL,
                          FILE_DEVICE_DISK,
                          FILE_DEVICE_SECURE_OPEN,
                          FALSE,
                          &filterDeviceObject);

  if(!NT_SUCCESS(status)){
    KdPrint(("CfaAddDevice: IoCreateDevice returned error %08lX\n", status));
    return(status);
  }

  //
  // initialize filter device object
  //
  KdPrint(("CfaAddDevice: filterDeviceObject->Flags = %08lX\n", filterDeviceObject->Flags));

  deviceExtension = filterDeviceObject->DeviceExtension;
  RtlZeroMemory(deviceExtension, sizeof(DEVICE_EXTENSION));

  deviceExtension->TargetDeviceObject =
    IoAttachDeviceToDeviceStack(filterDeviceObject, PhysicalDeviceObject);

  KdPrint(("TargetDevice->Characteristics = %08X\n",
    deviceExtension->TargetDeviceObject->Characteristics));

  KdPrint(("TargetDevice->Flags = %08X\n",
    deviceExtension->TargetDeviceObject->Flags));

  if(!deviceExtension->TargetDeviceObject){
    KdPrint(("CfaAddDevice: IoAttachDeviceToDeviceStack failed\n"));
    IoDeleteDevice(filterDeviceObject);
    return(STATUS_NO_SUCH_DEVICE);
  }

  deviceExtension->DeviceObject = filterDeviceObject;
  filterDeviceObject->Flags |= DO_DIRECT_IO;

  // finish initializing
  filterDeviceObject->Flags &= ~DO_DEVICE_INITIALIZING;

  return(STATUS_SUCCESS);
}


//
// This routine is called when IRP_MN_QUERY_CAPABILITIES has completed.
//
IO_COMPLETION_ROUTINE CfaQueryCapabilitiesCompletion;
NTSTATUS CfaQueryCapabilitiesCompletion(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp,
  IN PVOID Context
)
{
  UNREFERENCED_PARAMETER(DeviceObject);
  UNREFERENCED_PARAMETER(Context);

  if(Irp->PendingReturned){
    IoMarkIrpPending(Irp);
  }

  if(NT_SUCCESS(Irp->IoStatus.Status)){
    PIO_STACK_LOCATION irpStack = IoGetCurrentIrpStackLocation(Irp);
    PDEVICE_CAPABILITIES devcaps = irpStack->Parameters.DeviceCapabilities.Capabilities;
    KdPrint(("IRP_MN_QUERY_CAPABILITIES completed:\n"));
    // these are capabilities for the bus the device is attatched to
    KdPrint(("  Version = %d\n", devcaps->Version));
    KdPrint(("  LockSupported       = %d\n", devcaps->LockSupported));
    KdPrint(("  EjectSupported      = %d\n", devcaps->EjectSupported));
    KdPrint(("  Removable           = %d\n", devcaps->Removable));
    KdPrint(("  DockDevice          = %d\n", devcaps->DockDevice));
    KdPrint(("  UniqueID            = %d\n", devcaps->UniqueID));
    KdPrint(("  SilentInstall       = %d\n", devcaps->SilentInstall));
    KdPrint(("  RawDeviceOK         = %d\n", devcaps->RawDeviceOK));
    KdPrint(("  SurpriseRemovalOK   = %d\n", devcaps->SurpriseRemovalOK));
    KdPrint(("  NonDynamic          = %d\n", devcaps->NonDynamic));
    KdPrint(("  WarmEjectSupported  = %d\n", devcaps->WarmEjectSupported));
    KdPrint(("  Address             = %d\n", devcaps->Address));
  }

  return(Irp->IoStatus.Status);
}


//
// This is the forwarded IRP_MN_REMOVE_DEVICE completion routine.
//
IO_COMPLETION_ROUTINE CfaRemoveDeviceCompletion;
NTSTATUS CfaRemoveDeviceCompletion(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp,
  IN PVOID Context
)
{
  PKEVENT pEvent = (PKEVENT)Context;

  UNREFERENCED_PARAMETER(DeviceObject);
  UNREFERENCED_PARAMETER(Irp);

  KeSetEvent(pEvent, IO_NO_INCREMENT, FALSE);

  return(STATUS_MORE_PROCESSING_REQUIRED);
}


//
// This routine synchronously sends the Irp to the next lower driver.
//
NTSTATUS CfaForwardIrpSynchronous(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
)
{
  PDEVICE_EXTENSION deviceExtension;
  KEVENT event;
  NTSTATUS status;

  KeInitializeEvent(&event, NotificationEvent, FALSE);
  deviceExtension = DeviceObject->DeviceExtension;

  IoCopyCurrentIrpStackLocationToNext(Irp);
  IoSetCompletionRoutine(Irp, CfaRemoveDeviceCompletion, &event, TRUE, TRUE, TRUE);
  status = IoCallDriver(deviceExtension->TargetDeviceObject, Irp);
  if(STATUS_PENDING == status){
    KeWaitForSingleObject(&event, Executive, KernelMode, FALSE, NULL);
    status = Irp->IoStatus.Status;
  }

  return(status);
}


#define FILTER_DEVICE_PROPAGATE_CHARACTERISTICS  (FILE_READ_ONLY_DEVICE | FILE_FLOPPY_DISKETTE)


//
// This routine is called to dispatch PnP IRP
//
NTSTATUS CfaDispatchPnp(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
)
{
  PIO_STACK_LOCATION irpStack = IoGetCurrentIrpStackLocation(Irp);
  PDEVICE_EXTENSION deviceExtension = DeviceObject->DeviceExtension;
  NTSTATUS status;
  ULONG minorCode;

  minorCode = irpStack->MinorFunction;

  KdPrint(("CfaDispatchPnp: device %p Irp %p - function %X\n", DeviceObject, Irp, minorCode));

  switch(minorCode){
    case IRP_MN_QUERY_CAPABILITIES:
      IoCopyCurrentIrpStackLocationToNext(Irp);
      IoSetCompletionRoutine(Irp, CfaQueryCapabilitiesCompletion, (PVOID)minorCode, TRUE, TRUE, TRUE);
      return(IoCallDriver(deviceExtension->TargetDeviceObject, Irp));
    case IRP_MN_START_DEVICE:
      { PDEVICE_OBJECT targetDeviceObject = deviceExtension->TargetDeviceObject;
        ULONG pfs;
        KdPrint(("  processing IRP_MN_START_DEVICE\n"));
        // propagate vital characteristics except FILE_REMOVABLE_MEDIA
        pfs = targetDeviceObject->Characteristics & FILTER_DEVICE_PROPAGATE_CHARACTERISTICS;
        DeviceObject->Characteristics = (DeviceObject->Characteristics | pfs) & ~FILE_REMOVABLE_MEDIA;
      }
      break;
    case IRP_MN_REMOVE_DEVICE:
      { NTSTATUS status;
        KdPrint(("  processing IRP_MN_REMOVE_DEVICE\n"));
        status = CfaForwardIrpSynchronous(DeviceObject, Irp);
        IoDetachDevice(deviceExtension->TargetDeviceObject);
        IoDeleteDevice(DeviceObject);
        // complete the Irp
        Irp->IoStatus.Status = status;
        IoCompleteRequest(Irp, IO_NO_INCREMENT);
        return(status);
      }
  }

  return(CfaSendToNextDriver(DeviceObject, Irp));
}


//
// This routine is called for shutdown and flush.
//
NTSTATUS CfaShutdownFlush(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
)
{
  PDEVICE_EXTENSION deviceExtension = DeviceObject->DeviceExtension;

  KdPrint(("CfaShutdownFlush: DeviceObject %p Irp %p\n", DeviceObject, Irp));

  Irp->CurrentLocation++;
  Irp->Tail.Overlay.CurrentStackLocation++;

  return(IoCallDriver(deviceExtension->TargetDeviceObject, Irp));

}


//
// This routine is called to process power Irps.
//
NTSTATUS CfaDispatchPower(
  IN PDEVICE_OBJECT DeviceObject,
  IN PIRP Irp
)
{
  PDEVICE_EXTENSION deviceExtension = DeviceObject->DeviceExtension;

#if DBG
  {
    PIO_STACK_LOCATION irpStack = IoGetCurrentIrpStackLocation(Irp);
    ULONG minorCode = irpStack->MinorFunction;
    DbgPrint("CfaDispatchPower: device %p Irp %p - function %X\n", DeviceObject, Irp, minorCode);
  }
#endif

  PoStartNextPowerIrp(Irp);
  IoSkipCurrentIrpStackLocation(Irp);
  return(PoCallDriver(deviceExtension->TargetDeviceObject, Irp));
}


