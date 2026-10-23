<?php

namespace App\Http\Controllers;

use App\Exceptions\RpcError;
use App\Services\RpcDispatcher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RpcController extends Controller
{
    public function dispatch(Request $request, RpcDispatcher $dispatcher): JsonResponse
    {
        try {
            $oldRpcEnvelope = $dispatcher->dispatch(
                $request->user(),
                (string) $request->route('operation'),
                $request->all(),
            );
        } catch (RpcError $error) {
            return response()->json(['error' => $error->toEnvelope()], $error->httpStatus);
        }

        return response()->json(['data' => $oldRpcEnvelope]);
    }
}
